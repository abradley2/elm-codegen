module Internal.Render exposing (render)

{-| -}

import Elm.Syntax.Declaration
import Elm.Syntax.Exposing as Expose
import Elm.Syntax.Module
import Elm.Syntax.Range as Range
import Internal.Comments
import Internal.Compiler as Compiler
import Internal.Index as Index
import Internal.Write
import Set exposing (Set)


{-| -}
type alias File =
    { path : String
    , contents : String
    , warnings :
        List
            { declaration : String
            , warning : String
            }
    }


type alias Module =
    List String


type alias FileDetails =
    { moduleName : Module
    , aliases : List ( Module, String )
    , declarations : List Compiler.Declaration
    , index : Index.Index
    }


{-| -}
render :
    (List
        { group : Maybe String
        , members : List String
        }
     -> List String
    )
    -> FileDetails
    -> File
render toDocComment fileDetails =
    let
        rendered =
            List.foldl
                (\decl gathered ->
                    case decl of
                        Compiler.Comment comm ->
                            { gathered | declarations = Compiler.RenderedComment comm :: gathered.declarations }

                        Compiler.Block block ->
                            { gathered | declarations = Compiler.RenderedBlock block :: gathered.declarations }

                        Compiler.Declaration decDetails ->
                            let
                                result =
                                    decDetails.toBody fileDetails.index
                            in
                            { declarations =
                                Compiler.RenderedDecl (addDocs decDetails.docs result.declaration) :: gathered.declarations
                            , imports =
                                result.additionalImports ++ decDetails.imports ++ gathered.imports
                            , exposed =
                                addExposed decDetails.exposed result.declaration gathered.exposed
                            , exposedGroups =
                                case decDetails.exposed of
                                    Compiler.NotExposed ->
                                        gathered.exposedGroups

                                    Compiler.Exposed details ->
                                        ( details.group, decDetails.name ) :: gathered.exposedGroups
                            , hasPorts =
                                if gathered.hasPorts then
                                    gathered.hasPorts

                                else
                                    case result.declaration of
                                        Elm.Syntax.Declaration.PortDeclaration _ ->
                                            True

                                        _ ->
                                            False
                            , warnings =
                                case result.warning of
                                    Nothing ->
                                        gathered.warnings

                                    Just warn ->
                                        warn :: gathered.warnings
                            }
                )
                { imports = []
                , hasPorts = False
                , exposed = []
                , exposedGroups = []
                , declarations = []
                , warnings = []
                }
                fileDetails.declarations

        body =
            Internal.Write.write
                { moduleDefinition =
                    (if rendered.hasPorts then
                        Elm.Syntax.Module.PortModule

                     else
                        Elm.Syntax.Module.NormalModule
                    )
                        { moduleName = Compiler.nodify fileDetails.moduleName
                        , exposingList =
                            case rendered.exposed of
                                [] ->
                                    Compiler.nodify
                                        (Expose.All Range.emptyRange)

                                _ ->
                                    Compiler.nodify
                                        (Expose.Explicit
                                            (Compiler.nodifyAll rendered.exposed)
                                        )
                        }
                , aliases = fileDetails.aliases
                , imports =
                    rendered.imports
                        |> dedupImports
                        |> List.filterMap (Compiler.makeImport fileDetails.aliases)
                , declarations =
                    List.reverse rendered.declarations
                , comments =
                    Just
                        (Internal.Comments.addPart
                            Internal.Comments.emptyComment
                            (Internal.Comments.Markdown
                                (case rendered.exposedGroups of
                                    [] ->
                                        ""

                                    _ ->
                                        "\n"
                                            ++ (rendered.exposedGroups
                                                    |> List.sortBy
                                                        (\( group, _ ) ->
                                                            case group of
                                                                Nothing ->
                                                                    "zzzzzzzzz"

                                                                Just name ->
                                                                    name
                                                        )
                                                    |> groupExposing
                                                    |> toDocComment
                                                    |> String.join "\n\n"
                                               )
                                )
                            )
                        )
                }
    in
    { path =
        String.join "/" fileDetails.moduleName ++ ".elm"
    , contents = body
    , warnings = rendered.warnings
    }


dedupImports : List Module -> List Module
dedupImports mods =
    List.foldl
        (\mod ( set, gathered ) ->
            let
                stringName =
                    Compiler.fullModName mod
            in
            if Set.member stringName set then
                ( set, gathered )

            else
                ( Set.insert stringName set
                , mod :: gathered
                )
        )
        ( Set.empty, [] )
        mods
        |> Tuple.second
        |> List.sortBy Compiler.fullModName


addDocs maybeDoc decl =
    case maybeDoc of
        Nothing ->
            decl

        Just doc ->
            case decl of
                Elm.Syntax.Declaration.FunctionDeclaration func ->
                    Elm.Syntax.Declaration.FunctionDeclaration
                        { func
                            | documentation =
                                Just (Compiler.nodify doc)
                        }

                Elm.Syntax.Declaration.AliasDeclaration typealias ->
                    Elm.Syntax.Declaration.AliasDeclaration
                        { typealias
                            | documentation =
                                Just (Compiler.nodify doc)
                        }

                Elm.Syntax.Declaration.CustomTypeDeclaration typeDecl ->
                    Elm.Syntax.Declaration.CustomTypeDeclaration
                        { typeDecl
                            | documentation =
                                Just
                                    (Compiler.nodify doc)
                        }

                Elm.Syntax.Declaration.PortDeclaration sig ->
                    decl

                Elm.Syntax.Declaration.InfixDeclaration _ ->
                    decl

                Elm.Syntax.Declaration.Destructuring _ _ ->
                    decl


addExposed exposed declaration otherExposes =
    case exposed of
        Compiler.NotExposed ->
            otherExposes

        Compiler.Exposed details ->
            case declaration of
                Elm.Syntax.Declaration.FunctionDeclaration fn ->
                    let
                        fnName =
                            Compiler.denode (.name (Compiler.denode fn.declaration))
                    in
                    Expose.FunctionExpose fnName
                        :: otherExposes

                Elm.Syntax.Declaration.AliasDeclaration synonym ->
                    let
                        aliasName =
                            Compiler.denode synonym.name
                    in
                    Expose.TypeOrAliasExpose aliasName
                        :: otherExposes

                Elm.Syntax.Declaration.CustomTypeDeclaration myType ->
                    let
                        typeName =
                            Compiler.denode myType.name
                    in
                    if details.exposeConstructor then
                        Expose.TypeExpose
                            { name = typeName
                            , open = Just Range.emptyRange
                            }
                            :: otherExposes

                    else
                        Expose.TypeOrAliasExpose typeName
                            :: otherExposes

                Elm.Syntax.Declaration.PortDeclaration myPort ->
                    let
                        typeName =
                            Compiler.denode myPort.name
                    in
                    Expose.FunctionExpose typeName
                        :: otherExposes

                Elm.Syntax.Declaration.InfixDeclaration inf ->
                    otherExposes

                Elm.Syntax.Declaration.Destructuring _ _ ->
                    otherExposes


groupExposing : List ( Maybe String, String ) -> List { group : Maybe String, members : List String }
groupExposing items =
    List.foldr
        (\( maybeGroup, name ) acc ->
            case acc of
                [] ->
                    [ { group = maybeGroup, members = [ name ] } ]

                top :: groups ->
                    if matchName maybeGroup top.group then
                        { group = top.group
                        , members = name :: top.members
                        }
                            :: groups

                    else
                        { group = maybeGroup, members = [ name ] } :: acc
        )
        []
        items


matchName : Maybe a -> Maybe a -> Bool
matchName one two =
    case one of
        Nothing ->
            case two of
                Nothing ->
                    True

                _ ->
                    False

        Just oneName ->
            case two of
                Nothing ->
                    False

                Just twoName ->
                    oneName == twoName

module Gen exposing (main)

{-| -}

import Elm
import Elm.Pattern as Pattern
import Elm.Type as Type
import Generate
import Http


main : Program {} () ()
main =
    Platform.worker
        { init =
            \json ->
                ( ()
                , Cmd.batch
                    [ Generate.files
                        [ Elm.render file
                        ]
                    , Http.get
                        { url = "http://google.com"
                        , expect = Http.expectString (always ())
                        }
                    ]
                )
        , update =
            \msg model ->
                ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


file =
    Elm.file (Elm.moduleName [ "My", "Module" ])
        [ Elm.declaration "placeholder"
            (Elm.valueFrom (Elm.moduleAs [ "Json", "Decode" ] "Json")
                "map2"
            )
        , Elm.declaration "myRecord"
            (Elm.record
                [ ( "field1", Elm.string "My cool string" )
                , ( "field2", Elm.int 5 )
                , ( "field4", Elm.string "My cool string" )
                , ( "field5", Elm.int 5 )
                , ( "field6", Elm.string "My cool string" )
                , ( "field7"
                  , Elm.record
                        [ ( "field1", Elm.string "My cool string" )
                        , ( "field2", Elm.int 5 )
                        ]
                  )
                ]
            )
            |> Elm.expose
        ]

"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.default = (function () { return "\nmodule Generate exposing (main)\n\n{-| -}\n\nimport Elm\nimport Elm.Annotation as Type\nimport Gen.CodeGen.Generate as Generate\nimport Gen.Helper\n\n\nmain : Program {} () ()\nmain =\n    Platform.worker\n        { init =\n            \\json ->\n                ( ()\n                , Generate.files\n                    [ file\n                    ]\n                )\n        , update =\n            \\msg model ->\n                ( model, Cmd.none )\n        , subscriptions = \\_ -> Sub.none\n        }\n\n\nfile : Elm.File\nfile =\n    Elm.file [ \"HelloWorld\" ]\n        [ Elm.declaration \"hello\"\n            (Elm.string \"World!\")\n\n        -- Here's an example of using a helper file!\n        -- Add functions to codegen/helpers/{Whatever}.elm\n        -- run elm-codegen install\n        -- Then you can call those functions using import Gen.{Whatever}\n        , Elm.declaration \"usingAHelper\"\n            (Gen.Helper.add5 20)\n        ]\n"; });

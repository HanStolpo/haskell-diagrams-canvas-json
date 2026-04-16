{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

{- | CLI that mirrors the diagrams-canvas-json-viewer subcommands but writes
an image file instead of serving an interactive viewer. Each subcommand
parses its input JSON and calls into 'Diagrams.Backend.CanvasJson.Cairo'
to render a PNG, SVG, or JPEG.
-}
module Main (main) where

import Data.Aeson qualified as Aeson
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Diagrams.Backend.CanvasJson (CanvasDiagram, LayeredDiagram)
import Diagrams.Backend.CanvasJson.Cairo (
    Background (..),
    ImageFormat (..),
    ImageOptions (..),
    defaultImageOptions,
    formatFromExtension,
    renderCanvasDiagramTo,
    renderLayeredDiagramTo,
 )
import Options.Applicative
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr, stdin)

--------------------------------------------------------------------------------
-- Command line
--------------------------------------------------------------------------------

data Layout = LSingle | LBoard
    deriving (Show, Eq)

data Opts = Opts
    { optLayout :: !Layout
    , optSource :: !(Maybe FilePath)
    -- ^ 'Nothing' or @Just "-"@ reads stdin.
    , optOut :: !FilePath
    , optFormat :: !(Maybe ImageFormat)
    -- ^ @Nothing@ means derive from 'optOut' extension.
    , optWidth :: !Int
    , optHeight :: !Int
    , optPadding :: !Double
    , optBackground :: !(Maybe (Double, Double, Double, Double))
    -- ^ @Nothing@ means use 'defaultImageOptions' (solid white).
    , optTransparent :: !Bool
    , optJpegQuality :: !Int
    , optMirrorH :: !Bool
    , optMirrorV :: !Bool
    }

commandParser :: ParserInfo Opts
commandParser =
    info
        (layouts <**> helper)
        ( fullDesc
            <> progDesc
                "Render pre-rendered diagrams-canvas-json output to an image file \
                \(PNG, SVG, JPEG). Reads JSON from FILE or stdin."
        )
  where
    layouts =
        subparser
            ( command
                "single"
                (info (mkOpts LSingle) (progDesc "Render a single CanvasDiagram JSON"))
                <> command
                    "board"
                    ( info
                        (mkOpts LBoard)
                        (progDesc "Render a multi-layer board JSON with per-layer mask tinting")
                    )
            )

    mkOpts layout =
        Opts layout
            <$> optional
                ( argument
                    str
                    ( metavar "FILE"
                        <> help "Path to JSON input (default: stdin; \"-\" also reads stdin)"
                    )
                )
            <*> strOption
                ( long "out"
                    <> short 'o'
                    <> metavar "PATH"
                    <> help "Output image path (format derived from extension unless --format is given)"
                )
            <*> optional
                ( option
                    (eitherReader parseFormat)
                    ( long "format"
                        <> short 'f'
                        <> metavar "FORMAT"
                        <> help "Output format: png, svg, jpg/jpeg (default: from --out extension)"
                    )
                )
            <*> option auto (long "width" <> short 'w' <> value 800 <> metavar "PX" <> help "Output width in pixels (default 800)")
            <*> option auto (long "height" <> short 'h' <> value 800 <> metavar "PX" <> help "Output height in pixels (default 800)")
            <*> option auto (long "padding" <> value 0.9 <> metavar "FRAC" <> help "Fit padding factor 0-1 (default 0.9)")
            <*> optional
                ( option
                    (eitherReader parseBackground)
                    ( long "background"
                        <> short 'b'
                        <> metavar "R,G,B[,A]"
                        <> help "Background RGB 0-255 (alpha 0-1, default 1). Overrides --transparent."
                    )
                )
            <*> switch (long "transparent" <> help "Transparent background (ignored if --background is given)")
            <*> option auto (long "jpeg-quality" <> value 85 <> metavar "N" <> help "JPEG quality 1-100 (default 85)")
            <*> switch (long "mirror-h" <> help "Mirror the image horizontally (flip left/right)")
            <*> switch (long "mirror-v" <> help "Mirror the image vertically (flip top/bottom)")

parseFormat :: String -> Either String ImageFormat
parseFormat s = case map toLowerC s of
    "png" -> Right FormatPNG
    "svg" -> Right FormatSVG
    "jpg" -> Right FormatJPEG
    "jpeg" -> Right FormatJPEG
    _ -> Left ("Unknown format: " <> s <> " (expected png, svg, jpg or jpeg)")
  where
    toLowerC c = if c >= 'A' && c <= 'Z' then toEnum (fromEnum c + 32) else c

parseBackground :: String -> Either String (Double, Double, Double, Double)
parseBackground s = case splitCommas s of
    [r, g, b] -> (,,,) <$> num r <*> num g <*> num b <*> pure 1
    [r, g, b, a] -> (,,,) <$> num r <*> num g <*> num b <*> num a
    _ -> Left "Expected 3 or 4 comma-separated numbers"
  where
    num x = case reads x of
        [(n, "")] -> Right n
        _ -> Left ("Not a number: " <> x)

    splitCommas :: String -> [String]
    splitCommas xs = case break (== ',') xs of
        (a, []) -> [a]
        (a, _ : rest) -> a : splitCommas rest

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

main :: IO ()
main = do
    opts <- execParser commandParser
    fmt <- case optFormat opts of
        Just f -> pure f
        Nothing -> case formatFromExtension (optOut opts) of
            Just f -> pure f
            Nothing -> do
                hPutStrLn stderr $
                    "Cannot determine output format from path "
                        <> show (optOut opts)
                        <> "; pass --format png|svg|jpeg explicitly."
                exitFailure
    payload <- readInput (optSource opts)
    let imageOpts =
            defaultImageOptions
                { ioWidth = optWidth opts
                , ioHeight = optHeight opts
                , ioPadding = optPadding opts
                , ioBackground = case (optBackground opts, optTransparent opts) of
                    (Just (r, g, b, a), _) -> BackgroundSolid r g b a
                    (Nothing, True) -> BackgroundTransparent
                    (Nothing, False) -> ioBackground defaultImageOptions
                , ioJpegQuality = optJpegQuality opts
                , ioMirrorH = optMirrorH opts
                , ioMirrorV = optMirrorV opts
                }
    case optLayout opts of
        LSingle -> do
            cd <- decodeOrDie "CanvasDiagram" payload :: IO CanvasDiagram
            renderCanvasDiagramTo fmt (optOut opts) imageOpts cd
        LBoard -> do
            mld <- decodeOrDie "LayeredDiagram" payload :: IO LayeredDiagram
            renderLayeredDiagramTo fmt (optOut opts) imageOpts mld

-- | Read input payload, optionally from stdin.
readInput :: Maybe FilePath -> IO BL.ByteString
readInput src =
    BL.fromStrict <$> case src of
        Nothing -> BS.hGetContents stdin
        Just "-" -> BS.hGetContents stdin
        Just path -> BS.readFile path

decodeOrDie :: (Aeson.FromJSON a) => String -> BL.ByteString -> IO a
decodeOrDie label bytes = case Aeson.eitherDecode bytes of
    Right a -> pure a
    Left err -> do
        hPutStrLn stderr $ "Failed to decode " <> label <> ": " <> err
        exitFailure

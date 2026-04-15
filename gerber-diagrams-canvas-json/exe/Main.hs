{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Exception (SomeException, try)
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as BL
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as T
import Diagrams.Backend.CanvasJson (CanvasDiagram (..), encodeBBox, encodeCmd)
import Gerber.Diagrams.CanvasJson (
    BoardLayerSpec (..),
    BoardSpec (..),
    MultiLayerDiagram,
    buildBoardDiagram,
    clipToOutline,
    compositeLayers,
    defaultRenderOptions,
    renderGerber,
    renderGerberOutline,
    renderGerberRaw,
    syntheticOutline,
 )
import Options.Applicative
import System.Exit (exitFailure)
import System.FilePath (takeDirectory, takeFileName, (</>))
import System.IO (hPutStrLn, stderr)

{- | CLI commands. Every command emits JSON on stdout; view the output with
@diagrams-canvas-json-viewer@.
-}
data Command
    = ToJson !FilePath
    | OutlineToJson !FilePath
    | CompositeToJson !FilePath !FilePath !Bool
    | ClipToJson !FilePath !FilePath
    | BoardToJson !FilePath
    | LayersToJson ![FilePath]

commandParser :: ParserInfo Command
commandParser =
    info
        (commands <**> helper)
        ( fullDesc
            <> progDesc "Convert gerber files to canvas JSON. Pipe into diagrams-canvas-json-viewer to view."
        )
  where
    commands =
        subparser
            ( command "to-json" (info toJsonCmd (progDesc "Convert a gerber file to canvas JSON on stdout"))
                <> command "outline-to-json" (info outlineToJsonCmd (progDesc "Convert an outline gerber to a filled shape as canvas JSON"))
                <> command "composite-to-json" (info compositeToJsonCmd (progDesc "Composite base layer with inverted overlay to canvas JSON on stdout"))
                <> command "clip-to-json" (info clipToJsonCmd (progDesc "Clip a gerber layer to an outline shape as canvas JSON"))
                <> command "board-to-json" (info boardToJsonCmd (progDesc "Render board view from gerber layers to JSON on stdout"))
                <> command "layers-to-json" (info layersToJsonCmd (progDesc "Render multiple gerber files as a layer array JSON (for viewer grid / stack layouts)"))
            )

    toJsonCmd =
        ToJson
            <$> argument str (metavar "GERBER_FILE" <> help "Path to gerber file")

    outlineToJsonCmd =
        OutlineToJson
            <$> argument str (metavar "GERBER_FILE" <> help "Path to outline gerber file")

    compositeToJsonCmd =
        CompositeToJson
            <$> argument str (metavar "BASE" <> help "Base gerber layer")
            <*> argument str (metavar "OVERLAY" <> help "Overlay gerber layer (will be inverted)")
            <*> outlineFlag

    clipToJsonCmd =
        ClipToJson
            <$> argument str (metavar "CONTENT" <> help "Gerber layer to clip")
            <*> argument str (metavar "OUTLINE" <> help "Outline gerber (defines visible area)")

    boardToJsonCmd =
        BoardToJson
            <$> argument str (metavar "SPEC_FILE" <> help "Path to JSON board spec file")

    layersToJsonCmd =
        LayersToJson
            <$> some (argument str (metavar "GERBER_FILES..." <> help "Gerber files to render as named layers"))

    outlineFlag = switch (long "outline" <> help "Treat base layer as an outline (fill the path instead of stroking)")

main :: IO ()
main = do
    cmd <- execParser commandParser
    case cmd of
        ToJson filePath -> runToJson filePath
        OutlineToJson filePath -> runOutlineToJson filePath
        CompositeToJson basePath overlayPath outline -> runCompositeToJson basePath overlayPath outline
        ClipToJson contentPath outlinePath -> runClipToJson contentPath outlinePath
        BoardToJson specPath -> runBoardToJson specPath
        LayersToJson files -> runLayersToJson files

runToJson :: FilePath -> IO ()
runToJson filePath = do
    src <- T.readFile filePath
    case renderGerber defaultRenderOptions src of
        Left err -> do
            hPutStrLn stderr $ "Error: " <> err
            exitFailure
        Right diagram ->
            BL.putStr (Aeson.encode diagram <> "\n")

-- | Black fill colour for outlines
outlineColour :: (Double, Double, Double, Double)
outlineColour = (0, 0, 0, 1)

runOutlineToJson :: FilePath -> IO ()
runOutlineToJson filePath = do
    src <- T.readFile filePath
    case renderGerberOutline defaultRenderOptions outlineColour src of
        Left err -> do
            hPutStrLn stderr $ "Error: " <> err
            exitFailure
        Right diagram ->
            BL.putStr (Aeson.encode diagram <> "\n")

runCompositeToJson :: FilePath -> FilePath -> Bool -> IO ()
runCompositeToJson basePath overlayPath outline = do
    baseSrc <- T.readFile basePath
    overlaySrc <- T.readFile overlayPath
    case compositeGerbers outline baseSrc overlaySrc of
        Left err -> do
            hPutStrLn stderr $ "Error: " <> err
            exitFailure
        Right diagram ->
            BL.putStr (Aeson.encode diagram <> "\n")

compositeGerbers :: Bool -> T.Text -> T.Text -> Either String CanvasDiagram
compositeGerbers outline baseSrc overlaySrc = do
    base <-
        if outline
            then renderGerberOutline defaultRenderOptions outlineColour baseSrc
            else renderGerberRaw defaultRenderOptions baseSrc
    overlay <- renderGerberRaw defaultRenderOptions overlaySrc
    Right $ compositeLayers base overlay

runClipToJson :: FilePath -> FilePath -> IO ()
runClipToJson contentPath outlinePath = do
    contentSrc <- T.readFile contentPath
    outlineSrc <- T.readFile outlinePath
    case clipGerbers contentSrc outlineSrc of
        Left err -> do
            hPutStrLn stderr $ "Error: " <> err
            exitFailure
        Right diagram ->
            BL.putStr (Aeson.encode diagram <> "\n")

clipGerbers :: T.Text -> T.Text -> Either String CanvasDiagram
clipGerbers contentSrc outlineSrc = do
    content <- renderGerberRaw defaultRenderOptions contentSrc
    outline <- renderGerberRaw defaultRenderOptions outlineSrc
    Right $ clipToOutline content outline

--------------------------------------------------------------------------------
-- Board rendering
--------------------------------------------------------------------------------

runBoardToJson :: FilePath -> IO ()
runBoardToJson specPath = do
    result <- loadBoard specPath
    case result of
        Left err -> do
            hPutStrLn stderr $ "Error: " <> err
            exitFailure
        Right mld ->
            BL.putStr (Aeson.encode mld <> "\n")

{- | Load a board spec, read all referenced gerber files, and build
the board diagram.
-}
loadBoard :: FilePath -> IO (Either String MultiLayerDiagram)
loadBoard specPath = do
    specBytes <- BL.readFile specPath
    case Aeson.eitherDecode specBytes of
        Left err -> return (Left $ "Spec parse error: " <> err)
        Right spec -> do
            let specDir = takeDirectory specPath
                -- Collect all unique file paths
                allPaths =
                    maybe id (:) (bsOutline spec) $
                        bsThroughLayers spec
                            ++ map blsBase (bsLayers spec)
                uniquePaths = Map.fromList [(p, specDir </> p) | p <- allPaths]
            -- Render all gerber files
            rendered <- mapM renderFile (Map.toList uniquePaths)
            case sequence rendered of
                Left err -> return (Left err)
                Right pairs -> do
                    let fileMap = Map.fromList pairs
                        lookupFile p = case Map.lookup p fileMap of
                            Just d -> d
                            Nothing -> error $ "impossible: missing " <> p
                        layerDiagrams = map (lookupFile . blsBase) (bsLayers spec)
                        outlineDiagram = case bsOutline spec of
                            Just p -> lookupFile p
                            Nothing -> syntheticOutline layerDiagrams
                        throughDiagrams = map lookupFile (bsThroughLayers spec)
                        entries = zip (bsLayers spec) layerDiagrams
                    return (Right (buildBoardDiagram outlineDiagram throughDiagrams (bsBaseColor spec) entries))
  where
    renderFile :: (FilePath, FilePath) -> IO (Either String (FilePath, CanvasDiagram))
    renderFile (key, absPath) = do
        result <- try (T.readFile absPath) :: IO (Either SomeException T.Text)
        case result of
            Left exc -> return (Left $ "Failed to read " <> absPath <> ": " <> show exc)
            Right src ->
                case renderGerberRaw defaultRenderOptions src of
                    Left err -> return (Left $ "Failed to parse " <> absPath <> ": " <> err)
                    Right diagram -> return (Right (key, diagram))

--------------------------------------------------------------------------------
-- Layers (for viewer grid / stack layouts)
--------------------------------------------------------------------------------

runLayersToJson :: [FilePath] -> IO ()
runLayersToJson files = do
    layers <- loadLayers files
    BL.putStr (encodeLayers layers <> "\n")

-- | Read and render each gerber file, returning named diagrams.
loadLayers :: [FilePath] -> IO [(T.Text, CanvasDiagram)]
loadLayers files = do
    results <- mapM renderOne files
    case sequence results of
        Left err -> do
            hPutStrLn stderr $ "Error: " <> err
            exitFailure
        Right layers -> pure layers
  where
    renderOne fp = do
        result <- try (T.readFile fp) :: IO (Either SomeException T.Text)
        case result of
            Left exc -> pure . Left $ "Failed to read " <> fp <> ": " <> show exc
            Right src ->
                case renderGerber defaultRenderOptions src of
                    Left err -> pure . Left $ "Failed to parse " <> fp <> ": " <> err
                    Right cd -> pure . Right $ (T.pack (takeFileName fp), cd)

-- | Encode layers as a JSON array of @{name, bounds, commands}@.
encodeLayers :: [(T.Text, CanvasDiagram)] -> BL.ByteString
encodeLayers layers = Aeson.encode $ map encodeOne layers
  where
    encodeOne (name, cd) =
        let jp = cdPrecision cd
         in Aeson.object
                [ "name" Aeson..= name
                , "bounds" Aeson..= encodeBBox jp (cdBounds cd)
                , "commands" Aeson..= map (encodeCmd jp) (cdCommands cd)
                ]

{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Exception (SomeException, try)
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as BL
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
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
 )
import Options.Applicative
import System.Environment (lookupEnv)
import System.Exit (exitFailure)
import System.FilePath (takeDirectory, takeFileName, (</>))
import System.IO (hPutStrLn, stderr)
import Web.Scotty (get, raw, scotty, setHeader)

-- | Name of the bundled Canvas 2D JS library file.
jsBundleFileName :: FilePath
jsBundleFileName = "diagrams-canvas-json-web.iife.js"

-- | Name of the bundled PixiJS library file.
pixiJsBundleFileName :: FilePath
pixiJsBundleFileName = "diagrams-canvas-json-web-pixi.iife.js"

{- | Resolve the path to the JS bundle.

Uses the @DIAGRAMS_CANVAS_JSON_WEB_DIR@ environment variable if set,
otherwise falls back to the default path relative to the project root.
-}
resolveJsBundlePath :: IO FilePath
resolveJsBundlePath = do
    mDir <- lookupEnv "DIAGRAMS_CANVAS_JSON_WEB_DIR"
    pure $ case mDir of
        Just dir -> dir </> jsBundleFileName
        Nothing -> "diagrams-canvas-json-web" </> "dist" </> jsBundleFileName

-- | Read the JS bundle, failing with a helpful message if not found.
readJsBundle :: IO BL.ByteString
readJsBundle = do
    path <- resolveJsBundlePath
    result <- try (BL.readFile path) :: IO (Either SomeException BL.ByteString)
    case result of
        Right bs -> pure bs
        Left _ -> do
            hPutStrLn stderr $ "Error: Could not read JS bundle at: " <> path
            hPutStrLn stderr "Set DIAGRAMS_CANVAS_JSON_WEB_DIR to the directory containing the built JS library."
            hPutStrLn stderr "To build it: cd diagrams-canvas-json-web && npm run build:bundle"
            exitFailure

{- | Resolve the path to the PixiJS bundle.

Uses the @DIAGRAMS_CANVAS_JSON_WEB_DIR@ environment variable if set,
otherwise falls back to the default path relative to the project root.
-}
resolvePixiJsBundlePath :: IO FilePath
resolvePixiJsBundlePath = do
    mDir <- lookupEnv "DIAGRAMS_CANVAS_JSON_WEB_DIR"
    pure $ case mDir of
        Just dir -> dir </> pixiJsBundleFileName
        Nothing -> "diagrams-canvas-json-web" </> "dist" </> pixiJsBundleFileName

-- | Read the PixiJS bundle, failing with a helpful message if not found.
readPixiJsBundle :: IO BL.ByteString
readPixiJsBundle = do
    path <- resolvePixiJsBundlePath
    result <- try (BL.readFile path) :: IO (Either SomeException BL.ByteString)
    case result of
        Right bs -> pure bs
        Left _ -> do
            hPutStrLn stderr $ "Error: Could not read PixiJS bundle at: " <> path
            hPutStrLn stderr "Set DIAGRAMS_CANVAS_JSON_WEB_DIR to the directory containing the built JS library."
            hPutStrLn stderr "To build it: cd diagrams-canvas-json-web && npm run build:bundle-pixi"
            exitFailure

-- | CLI commands
data Command
    = ToJson !FilePath
    | View !FilePath !Int
    | OutlineToJson !FilePath
    | OutlineView !FilePath !Int
    | CompositeToJson !FilePath !FilePath !Bool
    | CompositeView !FilePath !FilePath !Bool !Int
    | ClipToJson !FilePath !FilePath
    | ClipView !FilePath !FilePath !Int
    | BoardToJson !FilePath
    | BoardView !FilePath !Int
    | ViewPixi !FilePath !Int
    | BoardViewPixi !FilePath !Int
    | GridView ![FilePath] !Int
    | GridViewPixi ![FilePath] !Int

commandParser :: ParserInfo Command
commandParser =
    info
        (commands <**> helper)
        ( fullDesc
            <> progDesc "Convert and view gerber files using diagrams-canvas-json"
        )
  where
    commands =
        subparser
            ( command "to-json" (info toJsonCmd (progDesc "Convert a gerber file to canvas JSON on stdout"))
                <> command "view" (info viewCmd (progDesc "View a gerber file in the browser via a local HTTP server"))
                <> command "outline-to-json" (info outlineToJsonCmd (progDesc "Convert an outline gerber to a filled shape as canvas JSON"))
                <> command "outline-view" (info outlineViewCmd (progDesc "View an outline gerber as a filled shape in the browser"))
                <> command "composite-to-json" (info compositeToJsonCmd (progDesc "Composite base layer with inverted overlay to canvas JSON on stdout"))
                <> command "composite-view" (info compositeViewCmd (progDesc "View base layer with inverted overlay in the browser"))
                <> command "clip-to-json" (info clipToJsonCmd (progDesc "Clip a gerber layer to an outline shape as canvas JSON"))
                <> command "clip-view" (info clipViewCmd (progDesc "View a gerber layer clipped to an outline shape in the browser"))
                <> command "board-to-json" (info boardToJsonCmd (progDesc "Render board view from gerber layers to JSON on stdout"))
                <> command "board-view" (info boardViewCmd (progDesc "View board rendering from gerber layers in the browser"))
                <> command "view-pixi" (info viewPixiCmd (progDesc "View a gerber file using PixiJS WebGL viewer"))
                <> command "board-view-pixi" (info boardViewPixiCmd (progDesc "View board rendering using PixiJS WebGL viewer"))
                <> command "grid-view" (info gridViewCmd (progDesc "View multiple gerber layers in an NxM grid"))
                <> command "grid-view-pixi" (info gridViewPixiCmd (progDesc "View multiple gerber layers in an NxM grid using PixiJS"))
            )

    toJsonCmd =
        ToJson
            <$> argument str (metavar "GERBER_FILE" <> help "Path to gerber file")

    viewCmd =
        View
            <$> argument str (metavar "GERBER_FILE" <> help "Path to gerber file")
            <*> portOpt

    outlineToJsonCmd =
        OutlineToJson
            <$> argument str (metavar "GERBER_FILE" <> help "Path to outline gerber file")

    outlineViewCmd =
        OutlineView
            <$> argument str (metavar "GERBER_FILE" <> help "Path to outline gerber file")
            <*> portOpt

    compositeToJsonCmd =
        CompositeToJson
            <$> argument str (metavar "BASE" <> help "Base gerber layer")
            <*> argument str (metavar "OVERLAY" <> help "Overlay gerber layer (will be inverted)")
            <*> outlineFlag

    compositeViewCmd =
        CompositeView
            <$> argument str (metavar "BASE" <> help "Base gerber layer")
            <*> argument str (metavar "OVERLAY" <> help "Overlay gerber layer (will be inverted)")
            <*> outlineFlag
            <*> portOpt

    clipToJsonCmd =
        ClipToJson
            <$> argument str (metavar "CONTENT" <> help "Gerber layer to clip")
            <*> argument str (metavar "OUTLINE" <> help "Outline gerber (defines visible area)")

    clipViewCmd =
        ClipView
            <$> argument str (metavar "CONTENT" <> help "Gerber layer to clip")
            <*> argument str (metavar "OUTLINE" <> help "Outline gerber (defines visible area)")
            <*> portOpt

    boardToJsonCmd =
        BoardToJson
            <$> argument str (metavar "SPEC_FILE" <> help "Path to JSON board spec file")

    boardViewCmd =
        BoardView
            <$> argument str (metavar "SPEC_FILE" <> help "Path to JSON board spec file")
            <*> portOpt

    viewPixiCmd =
        ViewPixi
            <$> argument str (metavar "GERBER_FILE" <> help "Path to gerber file")
            <*> portOpt

    boardViewPixiCmd =
        BoardViewPixi
            <$> argument str (metavar "SPEC_FILE" <> help "Path to JSON board spec file")
            <*> portOpt

    gridViewCmd =
        GridView
            <$> some (argument str (metavar "GERBER_FILES..." <> help "Gerber files to display in grid"))
            <*> portOpt

    gridViewPixiCmd =
        GridViewPixi
            <$> some (argument str (metavar "GERBER_FILES..." <> help "Gerber files to display in grid"))
            <*> portOpt

    portOpt = option auto (long "port" <> short 'p' <> value 3000 <> metavar "PORT" <> help "Port to serve on (default: 3000)")
    outlineFlag = switch (long "outline" <> help "Treat base layer as an outline (fill the path instead of stroking)")

main :: IO ()
main = do
    cmd <- execParser commandParser
    case cmd of
        ToJson filePath -> runToJson filePath
        View filePath port -> runView filePath port
        OutlineToJson filePath -> runOutlineToJson filePath
        OutlineView filePath port -> runOutlineView filePath port
        CompositeToJson basePath overlayPath outline -> runCompositeToJson basePath overlayPath outline
        CompositeView basePath overlayPath outline port -> runCompositeView basePath overlayPath outline port
        ClipToJson contentPath outlinePath -> runClipToJson contentPath outlinePath
        ClipView contentPath outlinePath port -> runClipView contentPath outlinePath port
        BoardToJson specPath -> runBoardToJson specPath
        BoardView specPath port -> runBoardView specPath port
        ViewPixi filePath port -> runViewPixi filePath port
        BoardViewPixi specPath port -> runBoardViewPixi specPath port
        GridView files port -> runGridView files port
        GridViewPixi files port -> runGridViewPixi files port

runToJson :: FilePath -> IO ()
runToJson filePath = do
    src <- T.readFile filePath
    case renderGerber defaultRenderOptions src of
        Left err -> do
            hPutStrLn stderr $ "Error: " <> err
            exitFailure
        Right diagram ->
            BL.putStr (Aeson.encode diagram <> "\n")

runView :: FilePath -> Int -> IO ()
runView filePath port = do
    src <- T.readFile filePath
    case renderGerber defaultRenderOptions src of
        Left err -> do
            hPutStrLn stderr $ "Error: " <> err
            exitFailure
        Right diagram ->
            serveViewer (T.pack filePath) diagram port

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

runOutlineView :: FilePath -> Int -> IO ()
runOutlineView filePath port = do
    src <- T.readFile filePath
    case renderGerberOutline defaultRenderOptions outlineColour src of
        Left err -> do
            hPutStrLn stderr $ "Error: " <> err
            exitFailure
        Right diagram ->
            serveViewer (T.pack filePath <> " (outline)") diagram port

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

runCompositeView :: FilePath -> FilePath -> Bool -> Int -> IO ()
runCompositeView basePath overlayPath outline port = do
    baseSrc <- T.readFile basePath
    overlaySrc <- T.readFile overlayPath
    case compositeGerbers outline baseSrc overlaySrc of
        Left err -> do
            hPutStrLn stderr $ "Error: " <> err
            exitFailure
        Right diagram -> do
            let name = T.pack basePath <> " + inverted " <> T.pack overlayPath
            putStrLn $ "  Base: " <> basePath <> (if outline then " (outline)" else "")
            putStrLn $ "  Overlay (inverted): " <> overlayPath
            serveViewer name diagram port

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

runClipView :: FilePath -> FilePath -> Int -> IO ()
runClipView contentPath outlinePath port = do
    contentSrc <- T.readFile contentPath
    outlineSrc <- T.readFile outlinePath
    case clipGerbers contentSrc outlineSrc of
        Left err -> do
            hPutStrLn stderr $ "Error: " <> err
            exitFailure
        Right diagram -> do
            let name = T.pack contentPath <> " clipped to " <> T.pack outlinePath
            putStrLn $ "  Content: " <> contentPath
            putStrLn $ "  Outline: " <> outlinePath
            serveViewer name diagram port

clipGerbers :: T.Text -> T.Text -> Either String CanvasDiagram
clipGerbers contentSrc outlineSrc = do
    content <- renderGerberRaw defaultRenderOptions contentSrc
    outline <- renderGerberRaw defaultRenderOptions outlineSrc
    Right $ clipToOutline content outline

serveViewer :: T.Text -> CanvasDiagram -> Int -> IO ()
serveViewer name diagram port = do
    let jsonBytes = Aeson.encode diagram
    jsBundle <- readJsBundle
    putStrLn $ "Serving gerber viewer at http://localhost:" <> show port
    scotty port $ do
        get "/" $ do
            setHeader "Content-Type" "text/html; charset=utf-8"
            raw . BL.fromStrict . TE.encodeUtf8 $ viewerHtml name

        get "/api/gerber/json" $ do
            setHeader "Content-Type" "application/json"
            raw jsonBytes

        get "/lib/diagrams-canvas-json-web.js" $ do
            setHeader "Content-Type" "application/javascript"
            raw jsBundle

viewerHtml :: T.Text -> T.Text
viewerHtml name =
    T.unlines
        [ "<!DOCTYPE html>"
        , "<html><head>"
        , "<meta charset=\"utf-8\">"
        , "<title>Gerber Viewer - " <> escapeHtml name <> "</title>"
        , "<style>"
        , viewerCss
        , "</style>"
        , "</head><body>"
        , "<h1>" <> escapeHtml name <> "</h1>"
        , "<div id=\"wrap\"></div>"
        , "<div id=\"error\"></div>"
        , "<script src=\"/lib/diagrams-canvas-json-web.js\"></script>"
        , "<script>"
        , "async function main() {"
        , "  const resp = await fetch('/api/gerber/json');"
        , "  if (!resp.ok) throw new Error('HTTP ' + resp.status);"
        , "  const diagram = await resp.json();"
        , "  DiagramsCanvasJson.createViewer({"
        , "    container: document.getElementById('wrap'),"
        , "    bounds: diagram.bounds,"
        , "    layers: [{ color: [0,0,0,1], commands: diagram.commands }],"
        , "  });"
        , "}"
        , "main().catch(e => {"
        , "  document.getElementById('error').textContent = 'Error: ' + e.message;"
        , "});"
        , "</script>"
        , "</body></html>"
        ]

-- | Shared CSS for all viewer pages.
viewerCss :: T.Text
viewerCss =
    T.unlines
        [ "* { margin: 0; padding: 0; box-sizing: border-box; }"
        , "html, body { height: 100%; overflow: hidden; background: #fff;"
        , "  font-family: system-ui, sans-serif; color: #333; }"
        , "body { display: flex; flex-direction: column; }"
        , "h1 { font-size: 1rem; padding: 0.4rem 0.8rem; background: #f5f5f5;"
        , "  border-bottom: 1px solid #ddd; flex-shrink: 0; }"
        , "#wrap { flex: 1; position: relative; overflow: hidden; }"
        , "#error { color: #cc0000; position: absolute; top: 50%; left: 50%;"
        , "  transform: translate(-50%, -50%); }"
        ]

escapeHtml :: T.Text -> T.Text
escapeHtml = T.replace "&" "&amp;" . T.replace "<" "&lt;" . T.replace ">" "&gt;" . T.replace "\"" "&quot;"

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

runBoardView :: FilePath -> Int -> IO ()
runBoardView specPath port = do
    result <- loadBoard specPath
    case result of
        Left err -> do
            hPutStrLn stderr $ "Error: " <> err
            exitFailure
        Right mld ->
            serveBoardViewer (T.pack specPath) mld port

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
                    bsOutline spec
                        : bsThroughLayers spec
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
                        outlineDiagram = lookupFile (bsOutline spec)
                        throughDiagrams = map lookupFile (bsThroughLayers spec)
                        entries = [(l, lookupFile (blsBase l)) | l <- bsLayers spec]
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

serveBoardViewer :: T.Text -> MultiLayerDiagram -> Int -> IO ()
serveBoardViewer name mld port = do
    let jsonBytes = Aeson.encode mld
    jsBundle <- readJsBundle
    putStrLn $ "Serving board viewer at http://localhost:" <> show port
    scotty port $ do
        get "/" $ do
            setHeader "Content-Type" "text/html; charset=utf-8"
            raw . BL.fromStrict . TE.encodeUtf8 $ boardViewerHtml name

        get "/api/gerber/json" $ do
            setHeader "Content-Type" "application/json"
            raw jsonBytes

        get "/lib/diagrams-canvas-json-web.js" $ do
            setHeader "Content-Type" "application/javascript"
            raw jsBundle

boardViewerHtml :: T.Text -> T.Text
boardViewerHtml name =
    T.unlines
        [ "<!DOCTYPE html>"
        , "<html><head>"
        , "<meta charset=\"utf-8\">"
        , "<title>Board Viewer - " <> escapeHtml name <> "</title>"
        , "<style>"
        , viewerCss
        , "</style>"
        , "</head><body>"
        , "<h1>" <> escapeHtml name <> "</h1>"
        , "<div id=\"wrap\"></div>"
        , "<div id=\"error\"></div>"
        , "<script src=\"/lib/diagrams-canvas-json-web.js\"></script>"
        , "<script>"
        , "async function main() {"
        , "  const resp = await fetch('/api/gerber/json');"
        , "  if (!resp.ok) throw new Error('HTTP ' + resp.status);"
        , "  const diagram = await resp.json();"
        , "  DiagramsCanvasJson.createViewer({"
        , "    container: document.getElementById('wrap'),"
        , "    bounds: diagram.bounds,"
        , "    layers: diagram.layers,"
        , "  });"
        , "}"
        , "main().catch(e => {"
        , "  document.getElementById('error').textContent = 'Error: ' + e.message;"
        , "});"
        , "</script>"
        , "</body></html>"
        ]

--------------------------------------------------------------------------------
-- Single-layer PixiJS viewer
--------------------------------------------------------------------------------

runViewPixi :: FilePath -> Int -> IO ()
runViewPixi filePath port = do
    src <- T.readFile filePath
    case renderGerber defaultRenderOptions src of
        Left err -> do
            hPutStrLn stderr $ "Error: " <> err
            exitFailure
        Right diagram ->
            serveViewerPixi (T.pack filePath) diagram port

serveViewerPixi :: T.Text -> CanvasDiagram -> Int -> IO ()
serveViewerPixi name diagram port = do
    let jsonBytes = Aeson.encode diagram
    pixiBundle <- readPixiJsBundle
    putStrLn $ "Serving PixiJS viewer at http://localhost:" <> show port
    scotty port $ do
        get "/" $ do
            setHeader "Content-Type" "text/html; charset=utf-8"
            raw . BL.fromStrict . TE.encodeUtf8 $ viewerPixiHtml name

        get "/api/gerber/json" $ do
            setHeader "Content-Type" "application/json"
            raw jsonBytes

        get "/lib/diagrams-canvas-json-web-pixi.js" $ do
            setHeader "Content-Type" "application/javascript"
            raw pixiBundle

viewerPixiHtml :: T.Text -> T.Text
viewerPixiHtml name =
    T.unlines
        [ "<!DOCTYPE html>"
        , "<html><head>"
        , "<meta charset=\"utf-8\">"
        , "<title>Gerber Viewer (PixiJS) - " <> escapeHtml name <> "</title>"
        , "<style>"
        , viewerCss
        , "</style>"
        , "</head><body>"
        , "<h1>" <> escapeHtml name <> " (PixiJS)</h1>"
        , "<div id=\"wrap\"></div>"
        , "<div id=\"error\"></div>"
        , "<script src=\"/lib/diagrams-canvas-json-web-pixi.js\"></script>"
        , "<script>"
        , "async function main() {"
        , "  const resp = await fetch('/api/gerber/json');"
        , "  if (!resp.ok) throw new Error('HTTP ' + resp.status);"
        , "  const diagram = await resp.json();"
        , "  await DiagramsCanvasJsonPixi.createPixiViewer({"
        , "    container: document.getElementById('wrap'),"
        , "    bounds: diagram.bounds,"
        , "    layers: [{ color: [0,0,0,1], commands: diagram.commands }],"
        , "  });"
        , "}"
        , "main().catch(e => {"
        , "  document.getElementById('error').textContent = 'Error: ' + e.message;"
        , "});"
        , "</script>"
        , "</body></html>"
        ]

--------------------------------------------------------------------------------
-- Board rendering (PixiJS viewer)
--------------------------------------------------------------------------------

runBoardViewPixi :: FilePath -> Int -> IO ()
runBoardViewPixi specPath port = do
    result <- loadBoard specPath
    case result of
        Left err -> do
            hPutStrLn stderr $ "Error: " <> err
            exitFailure
        Right mld ->
            serveBoardViewerPixi (T.pack specPath) mld port

serveBoardViewerPixi :: T.Text -> MultiLayerDiagram -> Int -> IO ()
serveBoardViewerPixi name mld port = do
    let jsonBytes = Aeson.encode mld
    pixiBundle <- readPixiJsBundle
    putStrLn $ "Serving PixiJS board viewer at http://localhost:" <> show port
    scotty port $ do
        get "/" $ do
            setHeader "Content-Type" "text/html; charset=utf-8"
            raw . BL.fromStrict . TE.encodeUtf8 $ boardViewerPixiHtml name

        get "/api/gerber/json" $ do
            setHeader "Content-Type" "application/json"
            raw jsonBytes

        get "/lib/diagrams-canvas-json-web-pixi.js" $ do
            setHeader "Content-Type" "application/javascript"
            raw pixiBundle

boardViewerPixiHtml :: T.Text -> T.Text
boardViewerPixiHtml name =
    T.unlines
        [ "<!DOCTYPE html>"
        , "<html><head>"
        , "<meta charset=\"utf-8\">"
        , "<title>Board Viewer (PixiJS) - " <> escapeHtml name <> "</title>"
        , "<style>"
        , viewerCss
        , "</style>"
        , "</head><body>"
        , "<h1>" <> escapeHtml name <> " (PixiJS)</h1>"
        , "<div id=\"wrap\"></div>"
        , "<div id=\"error\"></div>"
        , "<script src=\"/lib/diagrams-canvas-json-web-pixi.js\"></script>"
        , "<script>"
        , "async function main() {"
        , "  const resp = await fetch('/api/gerber/json');"
        , "  if (!resp.ok) throw new Error('HTTP ' + resp.status);"
        , "  const diagram = await resp.json();"
        , "  await DiagramsCanvasJsonPixi.createPixiViewer({"
        , "    container: document.getElementById('wrap'),"
        , "    bounds: diagram.bounds,"
        , "    layers: diagram.layers,"
        , "  });"
        , "}"
        , "main().catch(e => {"
        , "  document.getElementById('error').textContent = 'Error: ' + e.message;"
        , "});"
        , "</script>"
        , "</body></html>"
        ]

--------------------------------------------------------------------------------
-- Grid view
--------------------------------------------------------------------------------

runGridView :: [FilePath] -> Int -> IO ()
runGridView files port = do
    layers <- loadGridLayers files
    serveGridViewer layers port

runGridViewPixi :: [FilePath] -> Int -> IO ()
runGridViewPixi files port = do
    layers <- loadGridLayers files
    serveGridViewerPixi layers port

-- | Read and render each gerber file, returning named diagrams.
loadGridLayers :: [FilePath] -> IO [(T.Text, CanvasDiagram)]
loadGridLayers files = do
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

-- | Encode grid layers as a JSON array of {name, bounds, commands}.
encodeGridLayers :: [(T.Text, CanvasDiagram)] -> BL.ByteString
encodeGridLayers layers = Aeson.encode $ map encodeOne layers
  where
    encodeOne (name, cd) =
        let jp = cdPrecision cd
         in Aeson.object
                [ "name" Aeson..= name
                , "bounds" Aeson..= encodeBBox jp (cdBounds cd)
                , "commands" Aeson..= map (encodeCmd jp) (cdCommands cd)
                ]

serveGridViewer :: [(T.Text, CanvasDiagram)] -> Int -> IO ()
serveGridViewer layers port = do
    let jsonBytes = encodeGridLayers layers
    jsBundle <- readJsBundle
    putStrLn $ "Serving grid viewer at http://localhost:" <> show port
    scotty port $ do
        get "/" $ do
            setHeader "Content-Type" "text/html; charset=utf-8"
            raw . BL.fromStrict . TE.encodeUtf8 $ gridViewerHtml False

        get "/api/gerber/json" $ do
            setHeader "Content-Type" "application/json"
            raw jsonBytes

        get "/lib/diagrams-canvas-json-web.js" $ do
            setHeader "Content-Type" "application/javascript"
            raw jsBundle

serveGridViewerPixi :: [(T.Text, CanvasDiagram)] -> Int -> IO ()
serveGridViewerPixi layers port = do
    let jsonBytes = encodeGridLayers layers
    pixiBundle <- readPixiJsBundle
    putStrLn $ "Serving PixiJS grid viewer at http://localhost:" <> show port
    scotty port $ do
        get "/" $ do
            setHeader "Content-Type" "text/html; charset=utf-8"
            raw . BL.fromStrict . TE.encodeUtf8 $ gridViewerHtml True

        get "/api/gerber/json" $ do
            setHeader "Content-Type" "application/json"
            raw jsonBytes

        get "/lib/diagrams-canvas-json-web-pixi.js" $ do
            setHeader "Content-Type" "application/javascript"
            raw pixiBundle

gridViewerHtml :: Bool -> T.Text
gridViewerHtml isPixi =
    let (libScript, createCall) =
            if isPixi
                then
                    ( "/lib/diagrams-canvas-json-web-pixi.js"
                    , "await DiagramsCanvasJsonPixi.createPixiViewer"
                    )
                else
                    ( "/lib/diagrams-canvas-json-web.js"
                    , "DiagramsCanvasJson.createViewer"
                    )
        suffix = if isPixi then " (PixiJS)" else ""
     in T.unlines
            [ "<!DOCTYPE html>"
            , "<html><head>"
            , "<meta charset=\"utf-8\">"
            , "<title>Gerber Grid Viewer" <> suffix <> "</title>"
            , "<style>"
            , viewerCss
            , "</style>"
            , "</head><body>"
            , "<h1>Gerber Grid" <> suffix <> "</h1>"
            , "<div id=\"wrap\"></div>"
            , "<div id=\"error\"></div>"
            , "<script src=\"" <> libScript <> "\"></script>"
            , "<script>"
            , "async function main() {"
            , "  const resp = await fetch('/api/gerber/json');"
            , "  if (!resp.ok) throw new Error('HTTP ' + resp.status);"
            , "  const data = await resp.json();"
            , gridLayoutJs createCall
            , "}"
            , "main().catch(e => {"
            , "  document.getElementById('error').textContent = 'Error: ' + e.message;"
            , "});"
            , "</script>"
            , "</body></html>"
            ]

{- | Shared JavaScript for computing the NxM grid layout and creating
the viewer with interleaved CommandLayer / MaskLayer / CustomLayer.
-}
gridLayoutJs :: T.Text -> T.Text
gridLayoutJs createCall =
    T.unlines
        [ "  var n = data.length;"
        , "  if (n === 0) return;"
        , ""
        , "  // Find max bounds across all layers for uniform cell sizing"
        , "  var maxW = 0, maxH = 0;"
        , "  for (var i = 0; i < n; i++) {"
        , "    var b = data[i].bounds;"
        , "    maxW = Math.max(maxW, b.maxX - b.minX);"
        , "    maxH = Math.max(maxH, b.maxY - b.minY);"
        , "  }"
        , ""
        , "  // Grid dimensions"
        , "  var cols = Math.ceil(Math.sqrt(n));"
        , "  var rows = Math.ceil(n / cols);"
        , ""
        , "  // Layout constants (diagram units)"
        , "  var pad = maxW * 0.08;"
        , "  var titleH = maxH * 0.08;"
        , "  var cellW = maxW + pad * 2;"
        , "  var cellH = maxH + titleH + pad * 2;"
        , "  var gap = maxW * 0.06;"
        , ""
        , "  var layers = [];"
        , "  var labels = [];"
        , ""
        , "  for (var i = 0; i < n; i++) {"
        , "    var row = Math.floor(i / cols);"
        , "    var col = i % cols;"
        , "    // Cell origin (bottom-left, Y-up)"
        , "    var cx = col * (cellW + gap);"
        , "    var cy = (rows - 1 - row) * (cellH + gap);"
        , ""
        , "    // White background (CommandLayer)"
        , "    layers.push({"
        , "      commands: ["
        , "        ['B'], ['M', cx, cy], ['L', cx + cellW, cy],"
        , "        ['L', cx + cellW, cy + cellH], ['L', cx, cy + cellH],"
        , "        ['Z'], ['F', 255, 255, 255, 1]"
        , "      ]"
        , "    });"
        , ""
        , "    // Gerber content (MaskLayer, translated to cell center)"
        , "    var b = data[i].bounds;"
        , "    var gcx = (b.minX + b.maxX) / 2;"
        , "    var gcy = (b.minY + b.maxY) / 2;"
        , "    var contentCx = cx + cellW / 2;"
        , "    var contentCy = cy + pad + (cellH - titleH - pad * 2) / 2;"
        , "    var ox = contentCx - gcx;"
        , "    var oy = contentCy - gcy;"
        , ""
        , "    layers.push({"
        , "      color: [0, 0, 0, 1],"
        , "      commands: [['S'], ['T', 1, 0, 0, 1, ox, oy]]"
        , "        .concat(data[i].commands)"
        , "        .concat([['R']])"
        , "    });"
        , ""
        , "    labels.push({ text: data[i].name,"
        , "      x: cx + cellW / 2, y: cy + cellH - pad * 0.5 });"
        , "  }"
        , ""
        , "  // Title labels (CustomLayer)"
        , "  var fontSize = titleH * 0.7;"
        , "  layers.push({"
        , "    render: function(ctx, scale) {"
        , "      for (var i = 0; i < labels.length; i++) {"
        , "        var lbl = labels[i];"
        , "        ctx.save();"
        , "        ctx.translate(lbl.x, lbl.y);"
        , "        ctx.scale(1, -1);"
        , "        ctx.font = fontSize + 'px system-ui, sans-serif';"
        , "        ctx.textAlign = 'center';"
        , "        ctx.textBaseline = 'top';"
        , "        ctx.fillStyle = '#333';"
        , "        ctx.fillText(lbl.text, 0, 0);"
        , "        ctx.restore();"
        , "      }"
        , "    }"
        , "  });"
        , ""
        , "  // Overall bounds"
        , "  var totalW = cols * cellW + (cols - 1) * gap;"
        , "  var totalH = rows * cellH + (rows - 1) * gap;"
        , "  var bounds = { minX: -gap, minY: -gap,"
        , "    maxX: totalW + gap, maxY: totalH + gap };"
        , ""
        , "  " <> createCall <> "({"
        , "    container: document.getElementById('wrap'),"
        , "    bounds: bounds,"
        , "    layers: layers,"
        , "  });"
        ]

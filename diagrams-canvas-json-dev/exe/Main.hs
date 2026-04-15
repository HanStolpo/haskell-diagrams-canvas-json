{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}

module Main (main) where

import Data.Aeson qualified as A
import Data.ByteString.Lazy qualified as BL
import Data.Text.Lazy qualified as TL
import Diagrams.Backend.CanvasJson (CanvasDiagram, CanvasJson, canvasJsonOptions, renderCanvasJson)
import Diagrams.Backend.SVG (Options (..), SVG (..))
import Diagrams.Prelude hiding (text)
import Diagrams.TwoD.Text (Text, text)
import Graphics.Svg.Core (renderBS)
import Network.HTTP.Types.Status (status404)
import Web.Scotty (get, json, pathParam, raw, scotty, setHeader)
import Web.Scotty qualified as S

-- | Render a diagram to SVG ByteString
renderSvg :: QDiagram SVG V2 Double Any -> BL.ByteString
renderSvg d =
    let opts = SVGOptions (mkWidth 400) Nothing "" [] True
     in renderBS $ renderDia SVG opts d

-- | Render a diagram to CanvasDiagram JSON
renderJson :: QDiagram CanvasJson V2 Double Any -> CanvasDiagram
renderJson d = renderCanvasJson (canvasJsonOptions (mkWidth 400)) (d # pad 1.1)

-- Type alias for backend-polymorphic diagrams
type PolyDiagram b =
    ( Renderable (Path V2 Double) b
    , Renderable (Text Double) b
    , V b ~ V2
    , N b ~ Double
    )

-- | All the example diagrams from the diagrams quickstart guide
exampleNames :: [String]
exampleNames =
    [ "circle"
    , "styled-circle"
    , "side-by-side"
    , "superimposed"
    , "origin"
    , "horizontal"
    , "vertical"
    , "grid"
    , "beside-vectors"
    , "rotated-ellipses"
    , "snug-ellipses"
    , "transformations"
    , "translation"
    , "translation-effects"
    , "alignment"
    , "hexagon"
    , "polygon-nodes"
    , "tournament"
    ]

-- | Get an example diagram by name, polymorphic over backend
getExample :: (PolyDiagram b) => String -> Maybe (QDiagram b V2 Double Any)
getExample name = case name of
    "circle" -> Just exCircle
    "styled-circle" -> Just exStyledCircle
    "side-by-side" -> Just exSideBySide
    "superimposed" -> Just exSuperimposed
    "origin" -> Just exOrigin
    "horizontal" -> Just exHorizontal
    "vertical" -> Just exVertical
    "grid" -> Just exGrid
    "beside-vectors" -> Just exBesideVectors
    "rotated-ellipses" -> Just exRotatedEllipses
    "snug-ellipses" -> Just exSnugEllipses
    "transformations" -> Just exTransformations
    "translation" -> Just exTranslation
    "translation-effects" -> Just exTranslationEffects
    "alignment" -> Just exAlignment
    "hexagon" -> Just exHexagon
    "polygon-nodes" -> Just exPolygonNodes
    "tournament" -> Just exTournament
    _ -> Nothing

-- Example 1: First Circle
exCircle :: (PolyDiagram b) => QDiagram b V2 Double Any
exCircle = circle 1

-- Example 2: Styled Circle
exStyledCircle :: (PolyDiagram b) => QDiagram b V2 Double Any
exStyledCircle =
    circle 1
        # fc blue
        # lw veryThick
        # lc purple
        # dashingG [0.2, 0.05] 0

-- Example 3: Side-by-Side Circles
exSideBySide :: (PolyDiagram b) => QDiagram b V2 Double Any
exSideBySide = circle 1 # fc red # lw none ||| circle 1 # fc green # lw none

-- Example 4: Superimposed Shapes
exSuperimposed :: (PolyDiagram b) => QDiagram b V2 Double Any
exSuperimposed = square 1 # fc aqua `atop` circle 1

-- Example 5: Circle with Origin
exOrigin :: (PolyDiagram b) => QDiagram b V2 Double Any
exOrigin = circle 1 # showOrigin

-- Example 6: Horizontal Layout
exHorizontal :: (PolyDiagram b) => QDiagram b V2 Double Any
exHorizontal = circle 1 ||| square 2

-- Example 7: Vertical Layout
exVertical :: (PolyDiagram b) => QDiagram b V2 Double Any
exVertical = circle 1 === square 2

-- Example 8: Grid of Circles
exGrid :: (PolyDiagram b) => QDiagram b V2 Double Any
exGrid = vcat (replicate 3 circles)
  where
    circles = hcat (map circle [1 .. 6])

-- Example 9: Beside with Vectors
exBesideVectors :: (PolyDiagram b) => QDiagram b V2 Double Any
exBesideVectors = hcat' (with & sep .~ 1) [circleSqV1, circleSqV2]
  where
    circleSqV1 = beside (r2 (1, 1)) (circle 1) (square 2)
    circleSqV2 = beside (r2 (1, -2)) (circle 1) (square 2)

-- Example 10: Rotated Ellipses
exRotatedEllipses :: (PolyDiagram b) => QDiagram b V2 Double Any
exRotatedEllipses = ell ||| ell
  where
    ell = circle 1 # scaleX 0.5 # rotateBy (1 / 6)

-- Example 11: Snug Ellipses
exSnugEllipses :: (PolyDiagram b) => QDiagram b V2 Double Any
exSnugEllipses = ell # snugR <> ell # snugL
  where
    ell = circle 1 # scaleX 0.5 # rotateBy (1 / 6)

-- Example 12: Transformations
exTransformations :: (PolyDiagram b) => QDiagram b V2 Double Any
exTransformations = hcat' (with & sep .~ 1) [circleRect, circleRect2]
  where
    circleRect = circle 1 # scale 0.5 ||| square 1 # scaleX 0.3
    circleRect2 =
        circle 1
            # scale 0.5
            ||| square 1
            # scaleX 0.3
            # rotateBy (1 / 6)
            # scaleX 0.5

-- Example 13: Translation
exTranslation :: (PolyDiagram b) => QDiagram b V2 Double Any
exTranslation = circle 1 # translate (r2 (0.5, 0.3)) # showOrigin

-- Example 14: Translation Effects
exTranslationEffects :: (PolyDiagram b) => QDiagram b V2 Double Any
exTranslationEffects = hcat' (with & sep .~ 1) [circleSqT, circleSqHT, circleSqHT2]
  where
    circleSqT = square 1 `atop` circle 1 # translate (r2 (0.5, 0.3))
    circleSqHT = square 1 ||| circle 1 # translate (r2 (0.5, 0.3))
    circleSqHT2 = square 1 ||| circle 1 # translate (r2 (1.5, 0.3))

-- Example 15: Alignment
exAlignment :: (PolyDiagram b) => QDiagram b V2 Double Any
exAlignment = hrule (2 * sum sizes) === circles # centerX
  where
    circles = hcat (map (alignT . (`scale` circle 1)) sizes)
    sizes = [2, 5, 4, 7, 1, 3]

-- Example 16: Regular Polygon (Hexagon)
exHexagon :: (PolyDiagram b) => QDiagram b V2 Double Any
exHexagon = regPoly 6 1

-- Example 17: Nodes at Polygon Vertices
exPolygonNodes :: (PolyDiagram b) => QDiagram b V2 Double Any
exPolygonNodes = atPoints (trailVertices $ regPoly 6 1) (repeat node)
  where
    node = circle 0.2 # fc green

-- Example 18: Tournament Diagram with Labels
exTournament :: (PolyDiagram b) => QDiagram b V2 Double Any
exTournament = atPoints (trailVertices $ regPoly 5 1) (map node [1 .. 5])
  where
    node :: (PolyDiagram b) => Int -> QDiagram b V2 Double Any
    node n = text (show n) # fontSizeL 0.2 # fc white <> circle 0.2 # fc green

main :: IO ()
main = do
    putStrLn "Starting diagrams-canvas-json server on port 8080..."
    putStrLn "Available examples:"
    mapM_ (\name -> putStrLn $ "  - /api/example/" ++ name ++ "/svg") exampleNames
    mapM_ (\name -> putStrLn $ "  - /api/example/" ++ name ++ "/json") exampleNames

    scotty 8080 $ do
        -- List all available examples
        get "/api/examples" $ do
            json exampleNames

        -- Serve SVG for a specific example
        get "/api/example/:name/svg" $ do
            name <- pathParam "name"
            case getExample name :: Maybe (QDiagram SVG V2 Double Any) of
                Just diagram -> do
                    setHeader "Content-Type" "image/svg+xml"
                    raw $ renderSvg (diagram # pad 1.1)
                Nothing -> do
                    S.status status404
                    S.text $ TL.pack $ "Example not found: " ++ name ++ "\nAvailable: " ++ show exampleNames

        -- Serve JSON canvas commands for a specific example
        get "/api/example/:name/json" $ do
            name <- pathParam "name"
            case getExample name :: Maybe (QDiagram CanvasJson V2 Double Any) of
                Just diagram -> do
                    setHeader "Content-Type" "application/json"
                    raw $ A.encode (renderJson diagram)
                Nothing -> do
                    S.status status404
                    S.text $ TL.pack $ "Example not found: " ++ name ++ "\nAvailable: " ++ show exampleNames

        -- Health check endpoint
        get "/api/health" $ do
            S.text "OK"

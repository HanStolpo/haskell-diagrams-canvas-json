{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}

-- | A diagrams backend that outputs JSON commands for HTML Canvas rendering.
module Diagrams.Backend.CanvasJson
  ( -- * Backend token
    CanvasJson (..)
  , B

    -- * Rendering
  , renderCanvasJson
  , CanvasJsonOptions (..)
  , canvasJsonOptions

    -- * Canvas commands
  , CanvasCmd (..)
  , CanvasDiagram (..)
  ) where

import Control.Monad.State.Strict
import Data.Maybe (fromMaybe)
import Data.Aeson (ToJSON (..))
import Data.Aeson qualified as A
import Data.Tree (Tree (..))
import Data.Typeable (Typeable)
import Diagrams.Core.Compile (RNode (..), RTree, toRTree)
import Diagrams.Core.Transform (matrixHomRep)
import Diagrams.Core.Types (Annotation (..))
import Diagrams.Prelude hiding ((<>))
import Diagrams.TwoD.Attributes (FillTexture (..), LineTexture (..), Texture (..), getFillTexture, getLineTexture)
import Diagrams.TwoD.Text (Text (..), TextAlignment (..))
import GHC.Generics (Generic)

--------------------------------------------------------------------------------
-- Canvas Commands
--------------------------------------------------------------------------------

-- | Canvas drawing commands that map directly to the HTML Canvas API.
-- These are serialized as compact JSON arrays for efficiency.
data CanvasCmd
  = -- State management
    CmdSave
  | CmdRestore
  | -- Transformation (a, b, c, d, e, f)
    CmdTransform !Double !Double !Double !Double !Double !Double
  | -- Path commands (all use ABSOLUTE coordinates)
    CmdBeginPath
  | CmdMoveTo !Double !Double
  | CmdLineTo !Double !Double
  | CmdBezierTo !Double !Double !Double !Double !Double !Double
  | CmdQuadTo !Double !Double !Double !Double
  | CmdArc !Double !Double !Double !Double !Double
  | CmdClosePath
  | -- Style and drawing
    CmdFill !Double !Double !Double !Double -- RGBA
  | CmdStroke !Double !Double !Double !Double !Double -- RGBA + lineWidth
  | CmdSetLineCap !Int -- 0=butt, 1=round, 2=square
  | CmdSetLineJoin !Int -- 0=miter, 1=round, 2=bevel
  | CmdSetLineDash ![Double]
  | -- Text
    CmdFillText !String !Double !Double
  | CmdSetFont !String
  deriving (Show, Eq, Generic)

-- | Encode commands as compact JSON arrays for minimal payload size
instance ToJSON CanvasCmd where
  toJSON cmd = case cmd of
    CmdSave -> A.toJSON [A.String "S"]
    CmdRestore -> A.toJSON [A.String "R"]
    CmdTransform a b c d e f -> A.toJSON [A.String "T", n a, n b, n c, n d, n e, n f]
    CmdBeginPath -> A.toJSON [A.String "B"]
    CmdMoveTo x y -> A.toJSON [A.String "M", n x, n y]
    CmdLineTo x y -> A.toJSON [A.String "L", n x, n y]
    CmdBezierTo x1 y1 x2 y2 x y -> A.toJSON [A.String "C", n x1, n y1, n x2, n y2, n x, n y]
    CmdQuadTo x1 y1 x y -> A.toJSON [A.String "Q", n x1, n y1, n x, n y]
    CmdArc cx cy r startA endA -> A.toJSON [A.String "A", n cx, n cy, n r, n startA, n endA]
    CmdClosePath -> A.toJSON [A.String "Z"]
    CmdFill r g b a -> A.toJSON [A.String "F", n r, n g, n b, n a]
    CmdStroke r g b a lineW -> A.toJSON [A.String "K", n r, n g, n b, n a, n lineW]
    CmdSetLineCap c -> A.toJSON [A.String "LC", A.toJSON c]
    CmdSetLineJoin j -> A.toJSON [A.String "LJ", A.toJSON j]
    CmdSetLineDash ds -> A.toJSON (A.String "LD" : map n ds)
    CmdFillText t x y -> A.toJSON [A.String "FT", A.toJSON t, n x, n y]
    CmdSetFont f -> A.toJSON [A.String "SF", A.toJSON f]
    where
      n :: Double -> A.Value
      n = A.toJSON

-- | Bounding box for the diagram
data BBox = BBox
  { bbMinX :: !Double
  , bbMinY :: !Double
  , bbMaxX :: !Double
  , bbMaxY :: !Double
  }
  deriving (Show, Eq, Generic)

instance ToJSON BBox where
  toJSON bb =
    A.object
      [ "minX" A..= bbMinX bb
      , "minY" A..= bbMinY bb
      , "maxX" A..= bbMaxX bb
      , "maxY" A..= bbMaxY bb
      ]

-- | A complete canvas diagram with dimensions and commands
data CanvasDiagram = CanvasDiagram
  { cdWidth :: !Double
  , cdHeight :: !Double
  , cdBounds :: !BBox
  , cdCommands :: ![CanvasCmd]
  }
  deriving (Show, Eq, Generic)

instance ToJSON CanvasDiagram where
  toJSON cd =
    A.object
      [ "width" A..= cdWidth cd
      , "height" A..= cdHeight cd
      , "bounds" A..= cdBounds cd
      , "commands" A..= cdCommands cd
      ]

--------------------------------------------------------------------------------
-- Backend Definition
--------------------------------------------------------------------------------

-- | The CanvasJson backend token
data CanvasJson = CanvasJson
  deriving (Eq, Ord, Read, Show, Typeable)

-- | Convenient type alias for the backend
type B = CanvasJson

-- | Backend options
data CanvasJsonOptions = CanvasJsonOptions
  { _canvasJsonSize :: SizeSpec V2 Double
  }

-- | Default options with specified size
canvasJsonOptions :: SizeSpec V2 Double -> CanvasJsonOptions
canvasJsonOptions = CanvasJsonOptions

type instance V CanvasJson = V2
type instance N CanvasJson = Double

--------------------------------------------------------------------------------
-- Render Monad
--------------------------------------------------------------------------------

-- | Render state accumulating commands
data RenderState = RenderState
  { _rsCommands :: ![CanvasCmd] -- Commands in reverse order
  , _rsStyle :: !(Style V2 Double) -- Current accumulated style
  , _rsPos :: !(P2 Double) -- Current path position for offset conversion
  }

-- | The render monad
type RenderM a = State RenderState a

-- | Emit a canvas command
emit :: CanvasCmd -> RenderM ()
emit cmd = modify' $ \s -> s {_rsCommands = cmd : _rsCommands s}

-- | Update current position
setPos :: P2 Double -> RenderM ()
setPos p = modify' $ \s -> s {_rsPos = p}

-- | Get current position
getPos :: RenderM (P2 Double)
getPos = gets _rsPos

-- | Run render monad and extract commands
runRenderM :: RenderM () -> [CanvasCmd]
runRenderM m = reverse $ _rsCommands $ execState m (RenderState [] mempty origin)

--------------------------------------------------------------------------------
-- Backend Instance
--------------------------------------------------------------------------------

instance Backend CanvasJson V2 Double where
  newtype Render CanvasJson V2 Double = R {unR :: RenderM ()}

  type Result CanvasJson V2 Double = [CanvasCmd]

  data Options CanvasJson V2 Double = CanvasJsonOpts
    { _cjSize :: SizeSpec V2 Double
    }

  renderRTree _ _ rt = runRenderM (renderRTree' rt)

  adjustDia _ opts d = (opts, mempty, d)

instance Semigroup (Render CanvasJson V2 Double) where
  R r1 <> R r2 = R (r1 >> r2)

instance Monoid (Render CanvasJson V2 Double) where
  mempty = R (return ())

--------------------------------------------------------------------------------
-- RTree Rendering
--------------------------------------------------------------------------------

-- | Render an RTree to canvas commands
renderRTree' :: RTree CanvasJson V2 Double Annotation -> RenderM ()
renderRTree' (Node (RPrim p) _) = unR $ render CanvasJson p
renderRTree' (Node (RStyle sty) children) = do
  emit CmdSave
  oldSty <- gets _rsStyle
  modify' $ \s -> s {_rsStyle = sty Prelude.<> _rsStyle s}
  mapM_ renderRTree' children
  modify' $ \s -> s {_rsStyle = oldSty}
  emit CmdRestore
renderRTree' (Node (RAnnot _) children) = mapM_ renderRTree' children
renderRTree' (Node REmpty children) = mapM_ renderRTree' children

-- | Render a 2D transformation
renderTransform :: T2 Double -> RenderM ()
renderTransform tr = emit $ CmdTransform a1 a2 b1 b2 c1 c2
  where
    [[a1, a2], [b1, b2], [c1, c2]] = matrixHomRep tr

--------------------------------------------------------------------------------
-- Renderable Instances
--------------------------------------------------------------------------------

instance Renderable (Path V2 Double) CanvasJson where
  render _ p = R $ renderPath p

-- | Render a path with current style
renderPath :: Path V2 Double -> RenderM ()
renderPath p = do
  sty <- gets _rsStyle
  emit CmdBeginPath
  mapM_ renderLocTrail (pathTrails p)

  -- Apply fill if present
  case extractFillColor sty of
    Just (r, g, b, a) -> emit $ CmdFill r g b a
    Nothing -> return ()

  -- Apply stroke if present (default: black stroke with width 1)
  let lineW = fromMaybe 1 (extractLineWidth sty)
  case extractLineColor sty of
    Just (r, g, b, a) -> do
      -- Set line properties
      case getAttr sty of
        Just LineCapButt -> emit $ CmdSetLineCap 0
        Just LineCapRound -> emit $ CmdSetLineCap 1
        Just LineCapSquare -> emit $ CmdSetLineCap 2
        Nothing -> return ()
      case getAttr sty of
        Just LineJoinMiter -> emit $ CmdSetLineJoin 0
        Just LineJoinRound -> emit $ CmdSetLineJoin 1
        Just LineJoinBevel -> emit $ CmdSetLineJoin 2
        Nothing -> return ()
      case getAttr sty :: Maybe (Dashing Double) of
        Just (Dashing ds _) -> emit $ CmdSetLineDash ds
        Nothing -> return ()
      emit $ CmdStroke r g b a lineW
    Nothing ->
      -- Default stroke if no fill and no explicit line color
      case extractFillColor sty of
        Nothing -> emit $ CmdStroke 0 0 0 1 lineW
        Just _ -> return ()

-- | Render a located trail
renderLocTrail :: Located (Trail V2 Double) -> RenderM ()
renderLocTrail lt = do
  let startPt@(P (V2 x y)) = loc lt
  emit $ CmdMoveTo x y
  setPos startPt
  renderTrail (unLoc lt) startPt

-- | Render a trail starting from a point
renderTrail :: Trail V2 Double -> P2 Double -> RenderM ()
renderTrail t startPt = withTrail renderLine renderLoop t
  where
    renderLine ln = mapM_ renderSeg (lineSegments ln)
    renderLoop lp = do
      mapM_ renderSeg (lineSegments $ cutLoop lp)
      emit CmdClosePath
      setPos startPt -- Loop returns to start

-- | Render a single segment, converting offsets to absolute coordinates
renderSeg :: Segment Closed V2 Double -> RenderM ()
renderSeg (Linear (OffsetClosed offset)) = do
  P (V2 cx cy) <- getPos
  let V2 dx dy = offset
      newX = cx + dx
      newY = cy + dy
  emit $ CmdLineTo newX newY
  setPos (P (V2 newX newY))
renderSeg (Cubic (V2 c1x c1y) (V2 c2x c2y) (OffsetClosed (V2 dx dy))) = do
  P (V2 cx cy) <- getPos
  -- Control points are relative to current position
  let cp1x = cx + c1x
      cp1y = cy + c1y
      cp2x = cx + c2x
      cp2y = cy + c2y
      newX = cx + dx
      newY = cy + dy
  emit $ CmdBezierTo cp1x cp1y cp2x cp2y newX newY
  setPos (P (V2 newX newY))

instance Renderable (Text Double) CanvasJson where
  render _ (Text tr _al str) = R $ do
    emit CmdSave
    renderTransform tr
    sty <- gets _rsStyle
    emit $ CmdSetFont "16px sans-serif"
    case extractFillColor sty of
      Just (r, g, b, a) -> emit $ CmdFill r g b a
      Nothing -> return ()
    emit $ CmdFillText str 0 0
    emit CmdRestore

--------------------------------------------------------------------------------
-- Style Helpers
--------------------------------------------------------------------------------

-- | Extract fill color from style as RGBA (0-255 for RGB, 0-1 for alpha)
extractFillColor :: Style V2 Double -> Maybe (Double, Double, Double, Double)
extractFillColor sty = do
  ft <- getAttr sty :: Maybe (FillTexture Double)
  SomeColor c <- toColor (getFillTexture ft)
  let (r, g, b, a) = colorToRGBA c
  Just (r * 255, g * 255, b * 255, a)
  where
    toColor (SC (SomeColor c)) = Just (SomeColor c)
    toColor _ = Nothing

-- | Extract line color from style as RGBA
extractLineColor :: Style V2 Double -> Maybe (Double, Double, Double, Double)
extractLineColor sty = do
  lt <- getAttr sty :: Maybe (LineTexture Double)
  SomeColor c <- toColor (getLineTexture lt)
  let (r, g, b, a) = colorToRGBA c
  Just (r * 255, g * 255, b * 255, a)
  where
    toColor (SC (SomeColor c)) = Just (SomeColor c)
    toColor _ = Nothing

-- | Extract line width from style (simplified - uses Output measure)
extractLineWidth :: Style V2 Double -> Maybe Double
extractLineWidth sty = do
  lineW <- getAttr sty :: Maybe (LineWidth (Maybe Double))
  getLineWidth lineW

--------------------------------------------------------------------------------
-- High-level Rendering
--------------------------------------------------------------------------------

-- | Render a diagram to a CanvasDiagram
renderCanvasJson ::
  CanvasJsonOptions ->
  QDiagram CanvasJson V2 Double Any ->
  CanvasDiagram
renderCanvasJson opts d =
  let sz = _canvasJsonSize opts
      V2 w h = sizeFromSpec 400 sz

      -- Get bounding box
      bb = boundingBox d
      bounds = case getCorners bb of
        Nothing -> BBox 0 0 0 0
        Just (P (V2 minX minY), P (V2 maxX maxY)) ->
          BBox minX minY maxX maxY

      opts' = CanvasJsonOpts sz

      -- Render the diagram (raw coordinates, frontend handles scaling)
      rt = toRTree mempty d
      cmds = renderRTree CanvasJson opts' rt

   in CanvasDiagram w h bounds cmds

-- | Convert size spec to actual dimensions
sizeFromSpec :: Double -> SizeSpec V2 Double -> V2 Double
sizeFromSpec defSize spec = case getSpec spec of
  V2 (Just w) (Just h) -> V2 w h
  V2 (Just w) Nothing -> V2 w defSize
  V2 Nothing (Just h) -> V2 defSize h
  V2 Nothing Nothing -> V2 defSize defSize

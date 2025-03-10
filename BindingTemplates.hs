{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}


module Main
  ( main
  ) where


import           Control.Monad                  ( forM_
                                                , when
                                                )
import           Data.List                      ( sortOn )
import           Data.Text                      ( Text
                                                , pack
                                                , unpack
                                                )
import qualified Data.Text                     as T
import           System.Directory               ( createDirectoryIfMissing )


-- | Hole type and position relative to reference line.
data Hole
  = Pair Double Double    -- ^ Pair of holes with specified width and position.
  | Center Double         -- ^ A single hole in the center with position.


-- | A template is a list of hole positions.
newtype Template = Template { holes :: [Hole] } deriving Semigroup


-- | Coordinates for a point in mm.
type Point = (Double, Double)


-- | Boot sole length in mm.
type Bsl = Double


-- | Shift forward or backward.
class Shift a where
  shift :: Double -> a -> a


instance Shift Hole where
  shift amount h = case h of
    Pair w y -> Pair w $ y + amount
    Center y -> Center $ y + amount


instance Shift Template where
  shift amount t = Template $ shift amount <$> holes t


-- | A drawing is collection of SVG elements.
newtype Drawing = Drawing [Text] deriving (Semigroup, Monoid)


-- | Place toe and heel pieces into one template based on Bsl.
placeToeHeel :: Template -> Template -> Bsl -> Template
placeToeHeel toe heel bsl = shift (bsl / 2) toe <> shift (-bsl / 2) heel


-- | Draw a template.
template :: Text -> Template -> Drawing
template msg t =
  centerLines
    <> scalingRulers
    <> mconcat (hole <$> holes t)
    <> text (pageCenter1 + 35, baseHeel + 5) (msg <> ", Heel")
    <> text (pageCenter2 + 35, baseHeel + 5) (msg <> ", Toe")


text :: Point -> Text -> Drawing
text (x, y) msg = Drawing
  [ tagOpen
      "text"
      [ ("x"        , showT x)
      , ("y"        , showT y)
      , ("class"    , "small")
      , ("transform", "rotate(90 " <> showT x <> " " <> showT y <> ")")
      ]
    <> msg
    <> tagClose "text"
  ]


-- | Draw a hole.
hole :: Hole -> Drawing
hole h = case h of
  Pair w y -> target' (w / 2) y <> target' (-w / 2) y
  Center y -> target' 0 y

 where

  target' x y | y >= 0    = target (pageCenter2 + x, baseToe - y)
              | otherwise = target (pageCenter1 + x, baseHeel - y)


-- | Draws X and Y centerling lines for the template,
--   which align with the mid sole mark and the mid line on the skis.
centerLines :: Drawing
centerLines = mconcat
  -- Center lines.
  [ line (pageCenter1     , 0)        (pageCenter1     , pageHeight)
  , line (pageCenter2     , 0)        (pageCenter2     , pageHeight)
  -- Mount point lines.
  , line (pageCenter2 - 40, baseToe)  (pageCenter2 + 40, baseToe)
  , line (pageCenter1 - 40, baseHeel) (pageCenter1 + 40, baseHeel)
  -- Center trim line.
  , dashedLine (pageCenter , 0)            (pageCenter     , pageHeight)
  -- End trim lines.
  , dashedLine (0          , pageHeight)   (pageCenter     , pageHeight)
  , dashedLine (pageCenter , 0)            (pageWidth      , 0)
  -- Notch trim lines.
  , dashedLine (pageCenter1, baseHeel + 2) (pageCenter1 - 7, 0)
  , dashedLine (pageCenter1, baseHeel + 2) (pageCenter1 + 7, 0)
  , dashedLine (pageCenter2, baseToe - 2)  (pageCenter2 - 6, pageHeight)
  , dashedLine (pageCenter2, baseToe - 2)  (pageCenter2 + 6, pageHeight)
  ]


-- | Draws some rulers to check for scaling.
scalingRulers :: Drawing
scalingRulers = mconcat
  $ concat [line' <$> [baseHeel .. baseToe], line'' <$> m]

 where

  m =
    reverse [pageCenter1, pageCenter1 - 1 .. pageCenter1 - 40]
      <> [pageCenter1, pageCenter1 + 1 .. pageCenter1 + 40]

  line' y = line (0, y) (width $ y - 5, y)
  line'' x = line (x, baseToe) (x, baseToe - width (x - pageCenter1))

  width :: Double -> Double
  width n | (round n :: Int) `mod` 10 == 0 = 3
          | (round n :: Int) `mod` 5 == 0  = 2
          | otherwise                      = 1


-- | Page dimensions and parameters.

pageWidth :: Double
pageWidth = 190

pageHeight :: Double
pageHeight = 259

pageCenter :: Double
pageCenter = pageWidth / 2

pageCenter1 :: Double
pageCenter1 = pageCenter / 2

pageCenter2 :: Double
pageCenter2 = pageCenter / 2 + pageCenter

baseToe :: Double
baseToe = 255

baseHeel :: Double
baseHeel = 5


-- | Draws a line between two points.
line :: Point -> Point -> Drawing
line (x1, y1) (x2, y2) = Drawing
  [ tag
      "line"
      [ ("x1"          , showT x1)
      , ("y1"          , showT y1)
      , ("x2"          , showT x2)
      , ("y2"          , showT y2)
      , ("stroke"      , "black")
      , ("stroke-width", "0.1")
      ]
  ]


-- | Dashed line between two points.
dashedLine :: Point -> Point -> Drawing
dashedLine (x1, y1) (x2, y2) = Drawing
  [ tag
      "line"
      [ ("x1"              , showT x1)
      , ("y1"              , showT y1)
      , ("x2"              , showT x2)
      , ("y2"              , showT y2)
      , ("stroke"          , "black")
      , ("stroke-width"    , "0.1")
      , ("stroke-dasharray", "2 2")
      ]
  ]


-- | Draws a circle given a center point and a radius.
circle :: Point -> Double -> Drawing
circle (cx, cy) r = Drawing
  [ tag
      "circle"
      [ ("cx"          , showT cx)
      , ("cy"          , showT cy)
      , ("r"           , showT r)
      , ("fill"        , "none")
      , ("stroke"      , "black")
      , ("stroke-width", "0.1")
      ]
  ]


-- | Draws a target.
target :: Point -> Drawing
target (x, y) = mconcat
  [ circle (x, y) 2.5
  , line (x - 0.5, y)       (x + 0.5, y)
  , line (x      , y - 0.5) (x, y + 0.5)
  , line (x - 3  , y)       (x - 2  , y)
  , line (x + 2  , y)       (x + 3  , y)
  , line (x      , y - 3)   (x, y - 2)
  , line (x      , y + 2)   (x, y + 3)
  ]


-- | Converts Drawing to an SVG file.
svg :: Drawing -> Text
svg (Drawing elements) =
  T.unlines
    $  [ "<?xml version=\"1.0\"?>"
       , "<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.1//EN\""
       , "\"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd\">"
       , tagOpen
         "svg"
         [ ("xmlns"  , "http://www.w3.org/2000/svg")
         , ("version", "1.2")
         , ("width"  , showT pageWidth <> "mm")
         , ("height" , showT pageHeight <> "mm")
         , ("viewBox", "0 0 " <> showT pageWidth <> " " <> showT pageHeight)
         , ("style", "background-color:white")
         ]
       , tagOpen "style" []
       , ".small { font: 6px sans-serif; }"
       , tagClose "style"
       ]
    <> map ("  " <>) elements
    <> [tagClose "svg"]


-- | Formats an XML tag.
tag' :: Bool -> Text -> [(Text, Text)] -> Text
tag' open element attributes =
  "<"
    <> element
    <> mconcat
         [ " " <> name <> "=\"" <> value <> "\"" | (name, value) <- attributes ]
    <> (if open then " >" else " />")


tag :: Text -> [(Text, Text)] -> Text
tag = tag' False


tagOpen :: Text -> [(Text, Text)] -> Text
tagOpen = tag' True


tagClose :: Text -> Text
tagClose element = "</" <> element <> ">"


-- | Show for Text.
showT :: Show a => a -> Text
showT = pack . show


-- | Common Look toe.
lookToe :: Template
lookToe = Template [Pair 35 (-16.5), Pair 42 (-16.5 + 41.5)]


-- | Look Pivot.
pivot :: Bsl -> Template
pivot = placeToeHeel lookToe $ Template [Pair 21 82, Pair 29 (82 - 32)]


-- | Look SPX.
spx :: Bsl -> Template
spx = placeToeHeel lookToe $ Template [Pair 42 26, Pair 42 (26 - 105)]


-- | Look Rockerace.
rockerace :: Bsl -> Template
rockerace = placeToeHeel lookToe $ Template [Pair 42 59, Pair 42 (59 - 39)]


-- | Look R22 racing plate.
r22 :: Template
r22 = Template [Pair 12 164, Pair 35 99, Pair 35 (-52), Pair 35 (-171)]


-- | Salomon/Atomic Strive Demo.
striveDemo :: Template
striveDemo = Template
  [ pair toeBase
  , pair $ toeBase + toeLength
  , pair (-heelBase)
  , pair (-heelBase - heelLength)
  ]

 where

  toeLength  = 75
  heelLength = 80.5
  toeBase    = 136
  heelBase   = 144

  pair p = Pair 29.5 p


-- | Tyrolia PowerRail (PRD, Protector).
tyroliaPowerRail :: Template
tyroliaPowerRail = Template $ Pair 30 <$> [100, 200, -100, -200]


-- | Tyrolia Twin PR Base, set with specific BSL for maximum adjustability.
tyroliaTwinPrBase :: Bsl -> Template
tyroliaTwinPrBase = placeToeHeel
  (Template [Pair 30 (200 - bias), Pair 30 (100 - bias)])
  (Template [Pair 30 (bias - 100), Pair 30 (bias - 200)])
  where
  medianBsl = 316.5
  bias = medianBsl / 2


-- | Rossignol nordic IFP.
rossignolIFP :: Int -> Template
rossignolIFP euroSize = Template
  [ Center 37
  , Pair 26 (-10)
  , Center (-132)
  , Center (-200 - offset * 13)
  , Center (-235.5 - offset * 13)
  ]

 where

  offset :: Double
  offset | euroSize >= 36 && euroSize <= 38 = 0
         | euroSize >= 39 && euroSize <= 41 = 1
         | euroSize >= 42 && euroSize <= 44 = 2
         | euroSize >= 45 && euroSize <= 47 = 3
         | euroSize >= 48 && euroSize <= 50 = 4
         | otherwise = error $ "Unsupported euro size: " <> show euroSize


-- | Salomon Shift.
shift' :: Bsl -> Template
shift' = placeToeHeel (Template [Center (-20 + 65), Pair 30 (-20 - 70)])
                      (Template [Pair 36 15, Pair 36 (15 - 68)])

sth2Heel :: Template
sth2Heel = Template [Pair 32 28, Pair 32 (28 - 75)]

wardenToe :: Template
wardenToe = Template [Pair 40 (-15 + 65), Pair 40 (-15)]

-- | Salomon STH2.
sth2 :: Bsl -> Template
sth2 = placeToeHeel (Template [Pair 42 (-15 + 30), Pair 40 (-15)]) sth2Heel

-- | Salomon Warden 13, Strive 16
warden13 :: Bsl -> Template
warden13 = placeToeHeel wardenToe sth2Heel

-- | Salomon Warden 11, Strive 12/14, Stage 11
warden11 :: Bsl -> Template
warden11 = placeToeHeel wardenToe (Template [Pair 30 28, Pair 30 (28 - 80)])

-- | Marker Royal family (Jester, Griffon, Squire).
royal :: Bsl -> Template
royal = placeToeHeel royalToe
                     (Template [Pair 32 25, Pair 32 (25 - 80)])


royalToe :: Template
royalToe = Template [Pair 36 (-12 + 31), Pair 36 (-12)]


xcompHeel :: Template
xcompHeel = Template [Pair 20 12, Pair 40.5 (12 - 80)]


-- | Marker XComp.
xcomp :: Bsl -> Template
xcomp = placeToeHeel (Template [Pair 36 (-12), Center (-12 - 55)]) xcompHeel


-- | Marker XCell.
xcell :: Bsl -> Template
xcell = placeToeHeel royalToe xcompHeel


-- | Head Tyrolia.
tyrolia :: Bsl -> Template
tyrolia = placeToeHeel (Template [Pair 40 (-15 + 55), Pair 40 (-15)])
                       (Template [Pair 20 17, Pair 43.25 (17 - 95)])





-- | Head Tyrolia FreeFlex.
tyroliaFreeflex :: Bsl -> Template
tyroliaFreeflex bsl = shift (bsl / 2) $ Template
  [ Pair 40 (innerToeHoles + 55)
  , Pair 40 innerToeHoles
  , Pair 20 innerHeelHoles
  , Pair 43.25 $ innerHeelHoles - 95
  ]
 where
  innerToeHoles  = -15
  innerHeelHoles = innerToeHoles + 31.5 - nearest
  nearest        = snd $ head $ sortOn
    fst
    [ (abs $ bsl - opt, opt) | opt <- [270, 280 .. 360] ]


-- | Bishop BMF for NTN.
bmfNtn :: Bsl -> Template
bmfNtn bsl = shift (bsl / 2) $ Template
  [ Pair 38 (-25)
  , Pair 38 (-(25 + 38))
  , Pair 38 (-(25 + 38 + 38))
  , Pair 38 (-(25 + 38 + 38))
  , Center (-(25 + 38 + 38))
  , Center (-244)
  , Center (-(244 + 38))
  ]


-- | Library of all alpine and telemark templates.
templateLibrary :: [(Text, Text, Bsl -> Template)]
templateLibrary =
  [ ("look-pivot"      , "Look Pivot"                         , pivot)
  , ("look-spx"        , "Looks SPX"                          , spx)
  , ("look-rockerace"  , "Look Rockerace"                     , rockerace)
  , ("salomon-shift"   , "Salomon Shift"                      , shift')
  , ("salomon-sth2"    , "Salomon STH2"                       , sth2)
  , ("salomon-warden-11"  , "Salomon Warden 11, Strive 12/14" , warden11)
  , ("salomon-warden-13"  , "Salomon Warden 13, Strive 16"    , warden13)
  , ("marker-royal"    , "Marker Royal (Jester, Griffon, etc)", royal)
  , ("marker-xcomp"    , "Marker XComp"                       , xcomp)
  , ("marker-xcell"    , "Marker XCell"                       , xcell)
  , ("tyrolia"         , "Tyrolia"                            , tyrolia)
  , ("tyrolia-freeflex", "Tyrolia FreeFlex ST"                , tyroliaFreeflex)
  , ("tyrolia-twin-pr-base", "Tyrolia Twin PR Base w/ specific BSL for max adjustment", tyroliaTwinPrBase)
  , ("bishop-bmf-ntn"  , "Bishop"                             , bmfNtn)
  ]


-- | Generate binding templates.
main :: IO ()
main = do

  -- Alpine bindings.
  when (not test) $ forM_ [250 .. 350 :: Int] $ \bsl ->
    forM_ templateLibrary $ \(name, desc, t) -> do
      createDirectoryIfMissing False $ unpack name
      writeFile
          (unpack name <> "/" <> unpack name <> "-bsl-" <> show bsl <> ".svg")
        $ unpack
        $ svg
        $ template (desc <> ", BSL: " <> showT bsl <> " mm")
        $ t
        $ fromIntegral bsl

  -- Alpine plate and demo bindings.
  writeFile "look-r22.svg" $ unpack $ svg $ template "Look R22 Plate" r22
  writeFile "salomon-strive-demo.svg" $ unpack $ svg $ template
    "Salomon Strive Demo"
    striveDemo
  writeFile "tyrolia-power-rail.svg" $ unpack $ svg $ template
    "Tyrolia PowerRail"
    tyroliaPowerRail

  -- Nordic bindings.
  when (not test) $ forM_ [36 .. 50] $ \euroSize -> do
    createDirectoryIfMissing False "rossignol-ifp"
    writeFile ("rossignol-ifp/rossignol-ifp-euro-" <> show euroSize <> ".svg")
      $ unpack
      $ svg
      $ template ("Rossignol IFP, Euro Size: " <> showT euroSize)
      $ rossignolIFP euroSize


test :: Bool
test = False



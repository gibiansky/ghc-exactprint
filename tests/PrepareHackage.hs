{-# LANGUAGE OverloadedStrings #-}  --

import Data.Char
import Data.Monoid
import System.Directory
import System.FilePath.Posix
import Test.CommonUtils
import Turtle hiding (FilePath,(<.>))
import qualified Data.Set as Set
import qualified Data.Text as T
import qualified Data.Text.IO as T

main :: IO ()
main = do
  packages <- allCabalPackages
  -- packages <- allCabalPackagesTest
  echo (T.pack $ "number of packages:" ++ (show $ length packages))
  packageDirs <- drop 2 <$> getDirectoryContents (T.unpack workDir)
  echo (T.pack $ "packageDirs:" ++ (show $ take 5 packageDirs))
  let cond c = c == '.' || c == '-' || isDigit c
  let alreadyUnpacked = Set.fromList $ map (T.dropWhileEnd cond . T.pack) packageDirs
  _ <- shell ("mkdir -p " <> workDir) empty
  mapM_ (preparePackage alreadyUnpacked) packages

-- ---------------------------------------------------------------------

preparePackage :: Set.Set Text -> Text -> IO ()
preparePackage alreadyUnpacked package = do
  echo $ "preparePackage:" <> package
  if Set.member package alreadyUnpacked
     then echo $ "already unpacked:" <> package
     else preparePackage' package

preparePackage' :: Text -> IO ()
preparePackage' package = do
  (ec,dir) <- shellStrict ("cabal get --destdir=" <> workDir <> " " <> package) empty
  -- echo (T.pack $ "cabal get:" ++ show dir)
  echo (T.pack $ show ec)
  when (ec == ExitSuccess) $ do
    let bits = T.splitOn " " (head $ T.lines dir)
    echo (T.pack $ "cabal get:dir=" ++ show (last bits))
    cleanPackage (last bits)
  return ()

-- ---------------------------------------------------------------------

-- |Clean up whitespace in a package

cleanPackage :: Text -> IO ()
cleanPackage dir = do
  echo ("cleaning:" <> dir)
  fs <- findSrcFiles (T.unpack dir)
  let
    doOne :: FilePath -> IO ()
    doOne fn = do
      echo ("doOne:" <> T.pack fn)
      let tmpFn = fn <.> "clean"
      clean <- cleanupWhiteSpace fn
      T.writeFile tmpFn clean
      removeFile fn
      renameFile tmpFn fn
      return ()
  mapM_ doOne fs
  echo ("cleaned up:" <> dir)

-- ---------------------------------------------------------------------

allCabalPackagesTest :: IO [Text]
allCabalPackagesTest
  = return ["3d-graphics-examples","3dmodels","4Blocks","AAI","ABList"]
  -- = return ["airship"]


allCabalPackages :: IO [Text]
allCabalPackages = do
  -- let cmd = "cabal list --simple-output | awk '{ print $1 }' | uniq"
  let cmd = "cabal list --simple-output | awk '{ print $1 }' | sort | uniq"
  (_ec,r) <- shellStrict cmd empty
  let packages = T.lines r
  echo (T.pack $ show $ take 5 packages)
  return packages

-- ---------------------------------------------------------------------

workDir :: Text
workDir = "./hackage-roundtrip-work"

-- ---------------------------------------------------------------------

-- |strip trailing whitespace, and turn tabs into spaces
-- Note: using Text as its append performance beats String
cleanupWhiteSpace :: FilePath -> IO T.Text
cleanupWhiteSpace file = do
  -- buf@(GHC.StringBuffer _ len _) <- GHC.hGetStringBuffer file
  -- let contents = GHC.lexemeToString buf len
  contents <- readFileGhc file
  let cleaned = map cleanupOneLine (T.lines $ T.pack contents)
  return (T.unlines cleaned)

tabWidth :: Int
tabWidth = 8

nonBreakingSpace :: Char
nonBreakingSpace = '\xa0'

cleanupOneLine :: T.Text -> T.Text
cleanupOneLine str = str'
  where
    numSpacesForTab n = tabWidth - (n `mod` tabWidth)
    -- loop over the line, keeping current pos. Where a tab is found, insert
    -- spaces until the next tab stop. Discard any trailing whitespace.
    go col res cur =
      if T.null cur
         then res
         else
           case T.head cur of
             '\t' -> go (col + toAdd) (res <> T.replicate toAdd " ") (T.tail cur)
                where
                  toAdd = numSpacesForTab col
             '\xa0' -> go (col + 1) (T.snoc res ' ') (T.tail cur)
             -- nonBreakingSpace -> go (col + 1) (T.snoc res ' ') (T.tail cur)
             c -> go (col + 1) (T.snoc res c) (T.tail cur)
    str1 = go 0 T.empty str
    -- str2 = T.map (\c -> if c == nonBreakingSpace then ' ' else c) str1
    str' = T.dropWhileEnd isSpace str1

-- ---------------------------------------------------------------------

pwd :: IO FilePath
pwd = getCurrentDirectory

mcd :: FilePath -> IO ()
mcd = setCurrentDirectory
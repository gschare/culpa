{- stack
 runghc
 --package aeson
 --package html-entities
 --package text
 --package unordered-containers
 --package bytestring
 --package filepath
 --package directory
 --package pandoc
-}
{-# LANGUAGE OverloadedStrings #-}

import qualified Text.Pandoc as P (runIO, handleError)
import qualified Text.Pandoc.Templates as PT
import qualified HTMLEntities.Text as HTML (text)
import Text.DocLayout (render) -- Used to render Doc type into Text type.
import System.IO (writeFile)
import System.Directory (createDirectory, removeDirectoryRecursive, getDirectoryContents, doesDirectoryExist, copyFile)
import System.FilePath ((</>))
import Control.Monad (forM_)
--import Control.Arrow ((***))
import qualified Data.ByteString.Lazy as BS -- Using ByteStrings for efficiency since data file is large.
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
--import qualified Data.Text.Encoding as TE
import qualified Data.Aeson as J
import qualified Data.Aeson.Types as J (parseMaybe, parseEither, emptyObject)
--import Data.HashMap.Strict as HM (empty, toList)
import Data.Maybe (fromJust, fromMaybe)
import Data.Either (either)
import Data.List (sortOn, groupBy)
import Data.Function (on)
import Data.Map (Map)
import qualified Data.Map as Map (elems, (!))
import System.Exit (exitWith, ExitCode(..))

type DataId = T.Text
type DeptCode = T.Text  -- Maybe an enum instead?

data Dept = DeptKey DeptCode | Dept
    { deptCode    :: DeptCode
    --, deptCourses :: [DataId]
    , deptName    :: T.Text
    } deriving (Show, Read)

data Prof = ProfKey DataId | Prof
    { profId      :: DataId
    , profName    :: T.Text
    , profDepts   :: [Dept]
    , profCourses :: [Course]
    , profReviews :: [Review]
    } deriving (Show, Read)

data Course = MissingCourse | CourseKey DataId | Course
    { courseId      :: DataId
    , courseName    :: T.Text
    , courseDepts   :: [Dept]
    , courseProfs   :: [Prof]
    , courseReviews :: [Review]
    } deriving (Show, Read)

data Review = MissingReview | ReviewKey DataId | Review
    { reviewId      :: DataId
    , reviewDate    :: T.Text
    , reviewProf    :: Prof
    , reviewCourse  :: Course
    , reviewContent :: T.Text
    } deriving (Show, Read)

type DeptMap = Map DeptCode Dept
type ProfMap = Map DataId Prof
type CourseMap = Map DataId Course
type ReviewMap = Map DataId Review

data CulpaData =
    CulpaData { getDepts :: DeptMap
              , getProfs :: ProfMap
              , getCourses :: CourseMap
              , getReviews :: ReviewMap
              }

instance J.FromJSON Prof where
  parseJSON = J.withObject "Prof" $ \obj -> do
      i <- obj J..: "prof_id"
      n <- HTML.text <$> obj J..: "name"
      d <- map DeptKey <$> obj J..: "depts"
      c <- map CourseKey <$> obj J..: "courses"
      r <- map ReviewKey <$> obj J..: "reviews"
      return (Prof i n d c r)

instance J.ToJSON Prof where
  toJSON (Prof i n d c r) =
      J.object [ "prof_id" J..= i
               , "name" J..= n
               , "depts" J..= d
               , "courses" J..= c
               , "reviews" J..= r
               ]
  toJSON (ProfKey i) = J.toJSON i

instance J.FromJSON Course where
  parseJSON v = case v of
      J.Null -> return MissingCourse
      _      -> (J.withObject "Course" $ \obj -> do
              i <- obj J..: "course_id"
              n <- HTML.text <$> obj J..: "name"
              d <- map DeptKey <$> obj J..: "depts"
              p <- map ProfKey <$> obj J..: "profs"
              r <- map ReviewKey <$> obj J..: "reviews"
              return (Course i n d p r)) v

instance J.ToJSON Course where
  toJSON (Course i n d p r) =
      J.object [ "course_id" J..= i
               , "name" J..= n
               , "depts" J..= d
               , "profs" J..= p
               , "reviews" J..= r
               ]
  toJSON (CourseKey i) = J.toJSON i
  toJSON MissingCourse = J.Null

instance J.FromJSON Dept where
  parseJSON = J.withObject "Dept" $ \obj -> do
      c <- obj J..: "dept_code"
      n <- HTML.text <$> obj J..: "name"
      return (Dept c n)

instance J.ToJSON Dept where
  toJSON (Dept c n) =
      J.object [ "dept_code" J..= ("" :: T.Text) --c
               , "name" J..= ("" :: T.Text) --n
               ]
  toJSON (DeptKey code) = J.toJSON code

instance J.FromJSON Review where
  parseJSON v = case v of
      J.Null -> return MissingReview
      _      -> (J.withObject "Review" $ \obj -> do
              i <- obj J..: "review_id"
              d <- HTML.text <$> obj J..: "date"
              p <- ProfKey <$> obj J..: "prof_id"
              c <- let check result =
                           case result of
                               Nothing -> MissingCourse
                               Just cid -> CourseKey cid
                   in check <$> obj J..:! "course_id"
              t <- HTML.text <$> obj J..: "content"
              return (Review i d p c t)) v

instance J.ToJSON Review where
  toJSON (Review i d p c t) =
      J.object [ "review_id" J..= i
               , "date" J..= d
               , "prof" J..= p
               , "course" J..= c
               , "content" J..= t
               ]
  toJSON (ReviewKey i) = J.toJSON i
  toJSON MissingReview = J.Null

readJsonFile :: (J.FromJSON a) => FilePath -> IO a
readJsonFile filepath = handleFailure . J.eitherDecode <$> BS.readFile filepath
    where handleFailure result = case result of
                                   Left msg -> error msg
                                   Right val -> val

copyDir :: FilePath -> FilePath -> IO ()
copyDir src dst = do
    createDirectory dst
    dirContents <- getDirectoryContents src
    forM_ (filter (`notElem` [".", ".."]) dirContents) $ \name -> do
        let srcPath = src </> name
        let dstPath = dst </> name
        isDirectory <- doesDirectoryExist srcPath
        if isDirectory
           then copyDir srcPath dstPath
           else copyFile srcPath dstPath

assetsDir :: FilePath
assetsDir = "./assets/"

sourceDir :: FilePath
sourceDir = "./_data/"

templatesDir :: FilePath
templatesDir = "./_templates/"

targetDir :: FilePath
targetDir = "./_site/"

indexFile :: FilePath
indexFile = "./index.html"

loadTemplate :: FilePath -> IO (PT.Template T.Text)
loadTemplate filepath = do
    templateIO <- P.runIO $ PT.getTemplate filepath
    templateText <- P.handleError templateIO
    result <- PT.compileTemplate filepath templateText
    case result of
        Right template -> return template
        Left problem -> putStrLn problem >> (exitWith $ ExitFailure 1)

    {-
mdToHtml :: T.Text -> Either P.PandocError T.Text
mdToHtml md = P.runPure $ do
    doc <- P.readMarkdown P.def md
    P.writeHtml5String P.def doc
    -}

completeProf :: Prof -> DeptMap -> CourseMap -> ReviewMap -> Prof
completeProf prof depts courses reviews =
    let i = profId prof
        n = profName prof
        d = map (\(DeptKey k) -> depts Map.! k) $ profDepts prof
        c = map (\(CourseKey k) -> courses Map.! k) $ profCourses prof
        r = map (\(ReviewKey k) -> reviews Map.! k) $ profReviews prof
        r' = map (\rev ->
            let (CourseKey k) = reviewCourse rev in
            Review (reviewId rev)
                   (reviewDate rev)
                   (reviewProf rev)
                   (courses Map.! k)
                   (reviewContent rev)) r
    in Prof i n d c r'

makeProfPage :: Prof ->
                DeptMap -> CourseMap -> ReviewMap ->
                PT.Template T.Text ->
                T.Text
makeProfPage prof depts courses reviews template =
    let prof' = completeProf prof depts courses reviews in
    let context = J.object [ "prof" J..= prof' ]
        page = render Nothing $ PT.renderTemplate template context
    in page

-- TODO: sort this list
makeAllProfsPage :: ProfMap -> PT.Template T.Text -> T.Text
makeAllProfsPage profs template =
    let profList = sortOn profName $ Map.elems profs
        context = J.object [ "profs" J..= profList ]
        page = render Nothing $ PT.renderTemplate template context
    in page

writePage :: FilePath -> T.Text -> IO ()
writePage = TIO.writeFile

loadDepts :: IO DeptMap
loadDepts = {-do
    contents <- readJsonFile $ sourceDir </> "comments.json" :: IO [Comment]
    return . map (\cs -> (commentIssueUrl $ head cs, cs)) . groupBy ((==) `on` commentIssueUrl) $ contents
    -}
    readJsonFile $ sourceDir </> "departments.json"

loadProfs :: IO ProfMap
loadProfs = readJsonFile $ sourceDir </> "professors.json"

loadCourses :: IO CourseMap
loadCourses = readJsonFile $ sourceDir </> "courses.json"

loadReviews :: IO ReviewMap
loadReviews = readJsonFile $ sourceDir </> "reviews.json"

loadSourceFiles :: IO CulpaData
loadSourceFiles = do
    putStrLn "loading data files..."
    putStrLn "loading data: departments.json..."
    depts   <- loadDepts
    putStrLn "loading data: professors.json..."
    profs   <- loadProfs
    putStrLn "loading data: courses.json..."
    courses <- loadCourses
    putStrLn "loading data: reviews.json..."
    reviews <- loadReviews
    return $ CulpaData depts profs courses reviews

main :: IO ()
main = do
    -- Load source files
    CulpaData depts profs courses reviews <- loadSourceFiles

    -- Load templates
    putStrLn "loading templates..."
    putStrLn "loading template: dept-index.html..."
    deptIndexTemplate <- loadTemplate $ templatesDir </> "dept-index.html"
    putStrLn "loading template: dept.html..."
    deptTemplate      <- loadTemplate $ templatesDir </> "dept.html"
    putStrLn "loading template: prof-index.html..."
    profIndexTemplate <- loadTemplate $ templatesDir </> "prof-index.html"
    putStrLn "loading template: prof.html..."
    profTemplate      <- loadTemplate $ templatesDir </> "prof.html"
    putStrLn "loading template: course.html..."
    courseTemplate    <- loadTemplate $ templatesDir </> "course.html"
    putStrLn "loading template: review.html..."
    reviewTemplate    <- loadTemplate $ templatesDir </> "review.html"

    -- Prepare output
    putStrLn "creating _site/ ..."
    targetExists <- doesDirectoryExist targetDir
    if targetExists then removeDirectoryRecursive targetDir else return ()
    createDirectory targetDir

    putStrLn "creating _site/prof/ ..."
    createDirectory $ targetDir </> "prof"

    createDirectory $ targetDir </> "dept"
    createDirectory $ targetDir </> "course"
    createDirectory $ targetDir </> "review"
    --copyDir assetsDir (targetDir </> "assets/")

    -- Write files
    copyFile indexFile (targetDir </> "index.html")
    writeFile (targetDir </> ".nojekyll") "" -- Tell GitHub not to build with Jekyll

    -- Write navigation pages
        {-
    writePage (targetDir </> "dept" </> "index.html") <$>
        makeAllDeptsPage depts deptIndexTemplate
    writePage (targetDir </> "prof" </> "index.html") <$>
        makeAllProfsPage profs profIndexTemplate
        -}

    -- Write depts pages

    -- Write profs pages
    putStrLn "writing profs..."
    mapM_ (\prof -> do
        let page = makeProfPage prof depts courses reviews profTemplate
        writePage (   targetDir
                  </> "prof"
                  </> (T.unpack (profId prof) ++ ".html")
                  )
                  page)
        (Map.elems profs)

    -- Write courses pages

    -- Write reviews pages
    -- No.

    putStrLn "done"

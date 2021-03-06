{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE RecursiveDo         #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main where

------------------------------------------------------------------------------
import Data.Bool
import Data.Maybe
import Control.Monad.Fix (MonadFix)
import Data.Monoid (First(..), (<>))
import Data.Text (Text)
import qualified Data.Text as T
import Servant.API
import API
import Data.Proxy
import Text.Read (readMaybe)
import Reflex.Dom
------------------------------------------------------------------------------
import Servant.Reflex
import Servant.Reflex.Multi


api :: Proxy API
api = Proxy

main :: IO ()
main = mainWidget $ do
    divClass "example-base" run
    divClass "example-multi" runMulti


runMulti :: forall t m. (SupportsServantReflex t m,
                        DomBuilder t m,
                        DomBuilderSpace m ~ GhcjsDomSpace,
                        MonadFix m,
                        PostBuild t m,
                        MonadHold t m) => m ()
runMulti = do
    url <- baseUrlWidget
    el "br" blank
    let (_ :<|> _ :<|> sayHi :<|> dbl :<|> _ :<|> _ ) =
            clientA api (Proxy :: Proxy m) (Proxy :: Proxy []) (Proxy :: Proxy Int) url
    num :: Dynamic t (Either Text Double) <- fmap (note "No read" . readMaybe . T.unpack) . value <$> textInput def
    num2 :: Dynamic t (Either Text Double) <-  fmap (note "No read" . readMaybe . T.unpack) . value <$> textInput def
    -- dynText =<< holdDyn "waiting" (T.pack . show <$> num)
    -- numLabeled :: Event t (First Int, Double) <- zipListWithEvent (,) (First . Just <$> [0..]) num
    b <- button "Run dbl multi"
    reqCount <- count b
    r <- dbl ((\x y -> [x,y]) <$> num <*> num2) (tag (current reqCount) b)
    dynText =<< holdDyn "Waiting" (T.pack . show . fmapMaybe reqSuccess .snd <$> r)
    lastInd <- holdDyn Nothing (Just . fst <$> r)
    display lastInd

    divClass "demo-group" $ do
        nms <- fmap (fmap T.words . value) $ divClass "" $ do
            text "Names"
            textInput def
        grts <- fmap (fmap T.words . value) $ divClass "" $ do
            text "Greetings"
            textInput def
        gust <- fmap (value) $ divClass "gusto-input" $ checkbox False def
        b <- button "Go"
        r' <- sayHi (fmap QParamSome <$> nms) (fmap (:[]) $ grts) (constDyn [True, False]) (1 <$ b)
        dynText =<< holdDyn "Waiting" (T.pack . show . fmap (fmapMaybe reqSuccess) <$> r')
    return ()

run :: forall t m. (SupportsServantReflex t m,
                    DomBuilder t m,
                    DomBuilderSpace m ~ GhcjsDomSpace,
                    MonadFix m,
                    PostBuild t m,
                    MonadHold t m) => m ()
run = mdo

  reqCount <- count $ leftmost
              [() <$ unitBtn, () <$ intBtn, () <$ sayHiClicks, () <$ dblBtn, () <$ mpGo]
  -- Allow user to choose the url target for the request
  -- (alternatively we could just `let url = constDyn (BasePath "/")`)
  url <- baseUrlWidget
  el "br" (return ())
  dynText $ showBaseUrl <$> url

  el "br" (return ())

  -- Name the computed API client functions
  let (getUnit :<|> getInt :<|> sayhi :<|> dbl :<|> multi :<|> qna :<|> doRaw) =
        client api (Proxy :: Proxy m) url

  (unitBtn, intBtn) <- elClass "div" "demo-group" $ do
    unitBtn  <- divClass "unit-button" $ button "Get unit"
    intBtn   <- divClass "int-button"  $ button "Get int"

    unitResponse <- getUnit $ tag (current reqCount) unitBtn
    intResponse :: Event t (Int, ReqResult Int) <- getInt $ tag (current reqCount) intBtn

    score <- foldDyn (+) 0 (fmapMaybe reqSuccess (snd <$> intResponse))

    r <- holdDyn "Waiting" $ fmap showXhrResponse $
         leftmost [fmapMaybe response (snd <$> unitResponse)
                  ,fmapMaybe response (snd <$> intResponse)
                  ]
    divClass "unit-int-response" $ el "p" $ dynText r >> el "br" (return ()) >> text "Total: " >> display score
    return (unitBtn, intBtn)

  sayHiClicks <- elClass "div" "demo-group" $ do

    text "Name"
    el "br" $ return ()
    inp :: Dynamic t Text <- fmap value $ divClass "name-input" $ (textInput def)
    let checkedName = fmap (\i -> bool (QParamSome i) (QParamInvalid "Need a name") (T.null i)) inp
    el "br" $ return ()

    text "Greetings (space-separated)"
    el "br" $ return ()
    greetings <- fmap (fmap T.words . value) $
      divClass "greetings-input" $ (textInput def)

    el "br" $ return ()

    gusto <- fmap value $ divClass "gusto-input" $ checkbox False def

    el "br" $ return ()
    sayHiClicks :: Event t () <- divClass "hi-button" $ button "Say hi"
    let triggers = leftmost [sayHiClicks, () <$ updated inp]

    resp <- sayhi checkedName greetings gusto (tag (current reqCount) triggers)
    divClass "greeting-response" $ dynText =<<
      holdDyn "No hi yet" (leftmost [ fmapMaybe reqSuccess (snd <$> resp)
                                    , fmapMaybe reqFailure (snd <$> resp)])
    return sayHiClicks

  dblBtn <- elClass "div" "demo-group" $ do
    text "A Double to double"
    el "br" $ return ()
    dblinp <- fmap value $ divClass "double-input" $ textInput def
    (dblBtn) <- divClass "double-button" $ button "Double it"
    dblResp <- dbl (fmap (note "read failure" . readMaybe . T.unpack) $
                          dblinp) (tag (current reqCount) dblBtn)
    divClass "double-errors" $ dynText =<<
      holdDyn "(no errors)" (fmapMaybe reqFailure (snd <$> dblResp))
    el "br" (return ())
    divClass "double-result" $ el "p" $ dynText =<<
      holdDyn "No number yet" (fmap tShow $
                               fmapMaybe reqSuccess (snd <$> dblResp))
    return dblBtn

  mpGo <- elClass "div" "demo-group" $ do
    text "Multi-part path"
    b <- value <$> checkbox False def
    mpGo <- button "Test"
    multiResp <- multi b (tag (current reqCount) mpGo)
    dynText =<< holdDyn "No res yet" (fmap tShow $
                                      fmapMaybe reqSuccess $
                                      (snd <$> multiResp))
    return mpGo

  return ()

  el "br" $ return ()

  elClass "div" "demo-group" $ do
    text "JSON Unicode encoding test"
    txt <- value <$> textInput def
    ev  <- button "Question"
    let dQ = Right . Question <$> traceDyn "will send: " txt
    rr  <- qna dQ ev
    el "p" $
      dynText =<< holdDyn "No Answer" (unAnswer <$> fmapMaybe reqSuccess rr)

showXhrResponse :: XhrResponse -> Text
showXhrResponse (XhrResponse stat stattxt rbmay rtmay respHeaders) =
  T.unlines ["stat: " <> tShow stat
            ,"stattxt: " <> tShow stattxt
            ,"resp: " <> maybe "" showRB rbmay
            ,"rtext: " <> tShow rtmay
            ,"rHeaders: " <> tShow respHeaders]

tShow :: Show a => a -> Text
tShow = T.pack . show

showRB :: XhrResponseBody -> Text
showRB (XhrResponseBody_Default t) = tShow t
showRB (XhrResponseBody_Text t) = tShow t
showRB (XhrResponseBody_Blob t) = "<Blob>"
showRB (XhrResponseBody_ArrayBuffer t) = tShow t

note :: e -> Maybe a -> Either e a
note e = maybe (Left e) Right

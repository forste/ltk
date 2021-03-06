{-# OPTIONS_GHC
    -XExistentialQuantification
    -XMultiParamTypeClasses
    -XFunctionalDependencies
    -XNoMonomorphismRestriction -XCPP #-}
-----------------------------------------------------------------------------
--
-- Module      :  IDE.Core.Panes
-- Copyright   :  (c) Juergen Nicklisch-Franken, Hamish Mackenzie
-- License     :  GNU-GPL
--
-- Maintainer  :  <maintainer at leksah.org>
-- Stability   :  provisional21
-- Portability :  portable
--
-- | The basic definitions for all panes
--
-------------------------------------------------------------------------------

module Graphics.UI.Frame.Panes (

-- * Panes and pane layout
    PaneMonad(..)
,   IDEPane(..)
,   Pane(..)
,   RecoverablePane(..)
,   PaneDirection(..)
,   PanePathElement(..)
,   PanePath
,   PaneLayout(..)
,   PaneName
,   Connection(..)
,   Connections
,   StandardPath
,   FrameState(..)
,   signalDisconnectAll
) where

import Graphics.UI.Gtk hiding (get)
import System.Glib.GObject
import System.Glib.Signals
import Data.Maybe
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Typeable
import Graphics.UI.Editor.Basics
       (Connection(..), Connection, Connections)
import Control.Monad.IO.Class (MonadIO)

-- ---------------------------------------------------------------------
-- Panes and pane layout
--

--
-- | A path to a pane
--
type PanePath       =   [PanePathElement]

--
-- | An element of a path to a pane
--
data PanePathElement = SplitP PaneDirection | GroupP String
    deriving (Eq,Show,Read)

--
-- | The relative direction to a pane from the parent
--
data PaneDirection  =   TopP | BottomP | LeftP | RightP
    deriving (Eq,Show,Read)
  	
--
-- | Description of a window layout
-- Horizontal: top bottom Vertical: left right
--
data PaneLayout =       HorizontalP PaneLayout PaneLayout Int
                    |   VerticalP PaneLayout PaneLayout Int
                    |   TerminalP {
                                paneGroups   :: Map String PaneLayout
                            ,   paneTabs     :: Maybe PaneDirection
                            ,   currentPage  :: Int
                            ,   detachedId   :: Maybe String
                            ,   detachedSize :: Maybe (Int, Int) }
    deriving (Eq,Show,Read)

--
-- | All kinds of panes are instances of pane
--

class (Typeable alpha, PaneMonad delta) =>  Pane alpha delta | alpha -> delta  where

    getTopWidget    ::   alpha -> Widget
    -- ^ gets the top Widget of this pane
    paneId          ::   alpha -> String
    primPaneName    ::   alpha -> String

    paneName        ::   alpha -> PaneName
    paneName b      =   if getAddedIndex b == 0
                            then primPaneName b
                            else primPaneName b ++ "(" ++ show (getAddedIndex b) ++ ")"

    getAddedIndex   ::   alpha -> Int
    getAddedIndex _ =   0


class (Pane alpha delta, Typeable beta, Show beta, Read beta) => RecoverablePane alpha beta delta | beta  -> alpha, alpha -> beta  where

    saveState       ::   alpha -> delta (Maybe beta)
    recoverState    ::   PanePath -> beta -> delta (Maybe alpha)

    builder         ::   PanePath -> Notebook -> Window -> delta (Maybe alpha,Connections)

    -- getEditor    ::   Editor alpha

    makeActive      ::   alpha -> delta ()
    makeActive pane =   activateThisPane pane []

    closePane       ::   alpha -> delta Bool
    closePane       =   closeThisPane

    getPane         ::  delta (Maybe alpha)
    getPane         =   getThisPane

    forceGetPane    ::  Either PanePath String  -> delta alpha
    forceGetPane pp =   do  mbPane <- getOrBuildPane pp
                            case mbPane of
                                Nothing -> error "Can't get pane "
                                Just p -> return p

    getOrBuildPane  ::  Either PanePath String -> delta (Maybe alpha)
    getOrBuildPane  =   getOrBuildThisPane

    displayPane     ::  alpha -> Bool -> delta ()
    displayPane     =   displayThisPane

    getAndDisplayPane :: Either PanePath String -> Bool  -> delta (Maybe alpha)
    getAndDisplayPane pps b = do
        mbP <- getOrBuildThisPane pps
        case mbP of
            Nothing -> return Nothing
            Just p  -> do
                displayPane p b
                return (Just p)

    buildPane       ::  PanePath ->
                        Notebook ->
                        (PanePath -> Notebook -> Window -> delta (Maybe alpha,Connections)) ->
                        delta (Maybe alpha)
    buildPane       =   buildThisPane



class MonadIO delta =>  PaneMonad delta where
    setFrameState   ::  FrameState delta -> delta ()
    getFrameState   ::  delta (FrameState delta)
    runInIO         ::  forall alpha beta. (beta -> delta alpha) -> delta (beta -> IO alpha)
    panePathForGroup::  String -> delta PanePath

    getThisPane     ::  forall alpha beta . RecoverablePane alpha beta delta => delta (Maybe alpha)
    displayThisPane ::  forall alpha beta . RecoverablePane alpha beta delta => alpha -> Bool -> delta ()
    getOrBuildThisPane
                    ::  forall alpha beta . RecoverablePane alpha beta delta => Either PanePath String -> delta (Maybe alpha)
    buildThisPane   ::  forall alpha beta . RecoverablePane alpha beta delta =>
                        PanePath ->
                        Notebook ->
                        (PanePath -> Notebook -> Window -> delta (Maybe alpha,Connections)) ->
                        delta (Maybe alpha)
    activateThisPane :: forall alpha beta . RecoverablePane alpha beta delta =>  alpha -> Connections -> delta ()
    closeThisPane   ::  forall alpha beta . RecoverablePane alpha beta delta =>  alpha -> delta Bool

type PaneName = String

data IDEPane delta       =   forall alpha beta. (RecoverablePane alpha beta delta) => PaneC alpha

instance Eq (IDEPane delta) where
    (==) (PaneC x) (PaneC y) = paneName x == paneName y

instance Ord (IDEPane delta) where
    (<=) (PaneC x) (PaneC y) = paneName x <=  paneName y

instance Show (IDEPane delta) where
    show (PaneC x)    = "Pane " ++ paneName x

type StandardPath = PanePath

data FrameState delta = FrameState {
    windows         ::  [Window]
,   uiManager       ::  UIManager
,   panes           ::  Map PaneName (IDEPane delta)
,   paneMap         ::  (Map PaneName (PanePath, Connections))
,   activePane      ::  Maybe (PaneName, Connections)
,   panePathFromNB  ::  ! (Map Notebook PanePath)
,   layout          ::  PaneLayout}
    deriving Show

instance Show Window where
    show _ = "a Window"

instance Show UIManager where
    show _ = "a UIManager"

instance Show Connection where
    show _ = "a Connection"

instance Show Notebook where
    show _ = "a Notebook"

signalDisconnectAll :: Connections -> IO ()
signalDisconnectAll = mapM_ (\ (ConnectC s) -> signalDisconnect s)


-- Necessary with pre 10.1 verion of gtk2hs

#ifdef MIN_VERSION_gtk
#if MIN_VERSION_gtk(0,10,1)
#else
instance Eq Notebook
    where (==) a b = let (GObject pa, GObject pb) = (toGObject a, toGObject b)
                    in pa == pb
instance Ord Notebook
    where (<=) a b = let (GObject pa, GObject pb) = (toGObject a, toGObject b)
                    in pa <= pb
instance Eq Window
    where (==) a b = let (GObject pa, GObject pb) = (toGObject a, toGObject b)
                    in pa == pb
instance Eq Widget
    where (==) a b = let (GObject pa, GObject pb) = (toGObject a, toGObject b)
                    in pa == pb
#endif
#endif

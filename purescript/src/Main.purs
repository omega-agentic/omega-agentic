-- | Straylight Web Entry Point
module Main where

import Prelude

import Data.Const (Const)
import Data.Maybe (Maybe(..))
import Type.Proxy (Proxy(..))
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Aff.Class (class MonadAff)
import Effect.Class (liftEffect)
import Halogen as H
import Halogen.Aff as HA
import Halogen.HTML as HH

import Halogen.Subscription as HS
import Halogen.VDom.Driver (runUI)
import Web.DOM.ParentNode (QuerySelector(..), querySelector)
import Web.HTML (window)
import Web.HTML.HTMLDocument as HTMLDocument
import Web.HTML.HTMLElement as HTMLElement
import Web.HTML.Window (document)
import Web.Event.Event (preventDefault)
import Web.UIEvent.MouseEvent (MouseEvent, toEvent)

import Straylight.UI (cls, scanlineOverlay)
import Straylight.Router (Route(..), parseRoute, pushState, getPathname, onPopState)
import Straylight.Layout.Header as Header
import Straylight.Layout.Footer as Footer
import Straylight.Pages.Home as Home
import Straylight.Pages.Plan as Plan
import Straylight.Pages.Lean as Lean
import Straylight.Pages.Razorgirl as Razorgirl
import Straylight.Pages.Software as Software
import Straylight.Pages.Irc as Irc
import Straylight.Pages.Discord as Discord
import Straylight.Pages.OpenCode as OpenCode

-- ============================================================
-- MAIN ENTRY
-- ============================================================

main :: Effect Unit
main = launchAff_ do
  HA.awaitLoad
  doc <- liftEffect $ window >>= document
  let parent = HTMLDocument.toParentNode doc
  mbContainer <- liftEffect $ querySelector (QuerySelector "#straylight-app") parent
  case mbContainer >>= HTMLElement.fromElement of
    Nothing -> pure unit
    Just container -> void $ runUI appComponent unit container

-- ============================================================
-- APP COMPONENT
-- ============================================================

type AppState = { route :: Route }

data AppAction
  = Initialize
  | Navigate Route MouseEvent
  | RouteChanged String

type AppSlots =
  ( header :: H.Slot (Const Void) Void Unit
  , footer :: H.Slot (Const Void) Void Unit
  , home :: H.Slot (Const Void) Void Unit
  , plan :: H.Slot (Const Void) Void Unit
  , lean :: H.Slot (Const Void) Void Unit
  , razorgirl :: H.Slot (Const Void) Void Unit
  , software :: H.Slot (Const Void) Void Unit
  , irc :: H.Slot (Const Void) Void Unit
  , discord :: H.Slot (Const Void) Void Unit
  , opencode :: H.Slot (Const Void) Void Unit
  )

_header :: Proxy "header"
_header = Proxy

_footer :: Proxy "footer"
_footer = Proxy

_home :: Proxy "home"
_home = Proxy

_plan :: Proxy "plan"
_plan = Proxy

_lean :: Proxy "lean"
_lean = Proxy

_razorgirl :: Proxy "razorgirl"
_razorgirl = Proxy

_software :: Proxy "software"
_software = Proxy

_irc :: Proxy "irc"
_irc = Proxy

_discord :: Proxy "discord"
_discord = Proxy

_opencode :: Proxy "opencode"
_opencode = Proxy

appComponent :: forall q i o m. MonadAff m => H.Component q i o m
appComponent = H.mkComponent
  { initialState: const { route: OpenCode }  -- omega: opencode is home
  , render
  , eval: H.mkEval H.defaultEval
      { handleAction = handleAction
      , initialize = Just Initialize
      }
  }

handleAction :: forall o m. MonadAff m => AppAction -> H.HalogenM AppState AppAction AppSlots o m Unit
handleAction = case _ of
  Initialize -> do
    -- Get initial route
    path <- liftEffect getPathname
    H.modify_ _ { route = parseRoute path }
    -- Subscribe to popstate
    { emitter, listener } <- liftEffect HS.create
    liftEffect $ onPopState (\p -> HS.notify listener (RouteChanged p))
    void $ H.subscribe emitter
  
  Navigate route event -> do
    liftEffect $ preventDefault (toEvent event)
    liftEffect $ pushState $ routeToPath route
    H.modify_ _ { route = route }
  
  RouteChanged path -> do
    H.modify_ _ { route = parseRoute path }

routeToPath :: Route -> String
routeToPath = case _ of
  Home -> "/"           -- redirects to opencode
  OpenCode -> "/"       -- omega: opencode IS home
  Plan -> "/plan"
  Lean -> "/plan/lean"
  Razorgirl -> "/razorgirl"
  Software -> "/software"
  Irc -> "/irc"
  Discord -> "/discord"

render :: forall m. MonadAff m => AppState -> H.ComponentHTML AppAction AppSlots m
render state =
  HH.div
    [ cls [ "min-h-screen bg-background text-muted-foreground text-[15px] leading-relaxed" ] ]
    [ scanlineOverlay
    , renderHeader state
    , HH.main
        [ cls [ "max-w-[900px] mx-auto px-8 py-12" ] ]
        [ renderPage state.route ]
    , HH.slot_ _footer unit Footer.footer unit
    ]

renderPage :: forall m. MonadAff m => Route -> H.ComponentHTML AppAction AppSlots m
renderPage = case _ of
  Home -> HH.slot_ _home unit Home.homePage unit
  Plan -> HH.slot_ _plan unit Plan.planPage unit
  Lean -> HH.slot_ _lean unit Lean.leanPage unit
  Razorgirl -> HH.slot_ _razorgirl unit Razorgirl.razorgirlPage unit
  Software -> HH.slot_ _software unit Software.softwarePage unit
  Irc -> HH.slot_ _irc unit Irc.ircPage unit
  Discord -> HH.slot_ _discord unit Discord.discordPage unit
  OpenCode -> HH.slot_ _opencode unit OpenCode.openCodePage unit

-- ============================================================
-- HEADER (inline for nav actions)
-- ============================================================

renderHeader :: forall m. MonadAff m => AppState -> H.ComponentHTML AppAction AppSlots m
renderHeader state =
  HH.slot_ _header unit Header.header 
    { currentPath: routeToPath state.route
    , themeLock: routeThemeLock state.route
    }

-- | Pages that lock the theme (ultraviolence mode)
routeThemeLock :: Route -> Maybe String
routeThemeLock = case _ of
  -- Villa Straylight papers lock to memphis black
  Plan -> Just "ono-memphis"
  Lean -> Just "ono-memphis"
  _ -> Nothing

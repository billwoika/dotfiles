# Browser Developer Tools

For web development, the browser's built-in developer tools are the
primary debugging surface. They sit at the boundary between your
server, your frontend code, and the rendering engine — the only tool
that shows you what is actually happening from the user's perspective.
Every modern browser (Chrome, Firefox, Safari, Edge) ships a full
debugging environment. The capabilities are broadly equivalent across
browsers; Chrome DevTools is the reference implementation that others
track.

The framework's position: browser developer tools are not optional.
An engineer who reaches for `console.log` before opening the Network
panel or setting a breakpoint in Sources is working with one hand
tied. This page covers every major capability in enough detail to make
each one usable, not just known.

**Opening DevTools:**

| Platform | Shortcut |
|----------|----------|
| macOS | Cmd+Option+I (or Cmd+Option+J for Console) |
| Linux/Windows | F12 (or Ctrl+Shift+I) |
| Right-click any element | "Inspect" jumps directly to Elements |

## Elements panel

The Elements panel shows the live DOM and the styles applied to every
node. This is where CSS debugging happens.

### The DOM tree

The left pane is the rendered DOM — not your source HTML, but what
the browser constructed after parsing, script execution, and template
rendering. Elements you dynamically create via JavaScript appear here.
Elements removed by frameworks do not.

- **Edit HTML live** — double-click any element to rewrite its markup.
  Changes are immediate and non-persistent (reload reverts).
- **Drag to reorder** — move elements in the tree to test layout
  changes.
- **Delete nodes** — select and press Delete. Useful for isolating
  layout problems by removing surrounding elements.
- **Force state** — right-click an element and force `:hover`,
  `:active`, `:focus`, or `:visited` states to debug pseudo-class
  styles without mousing.
- **Break on** — right-click > "Break on" > subtree modifications,
  attribute modifications, or node removal. This triggers a debugger
  breakpoint when JavaScript modifies this element — invaluable for
  finding which code is mutating the DOM.

### The Styles pane

The right pane shows every CSS rule that applies to the selected
element, in specificity order (most specific at top). This is where
you answer "why does this element look wrong?"

- **Specificity cascade** — rules are listed from most to least
  specific. Overridden properties show with a strikethrough.
  The rule that wins is always at the top of the stack for that
  property.
- **Edit values live** — click any value to change it. Color values
  get a color picker. Numeric values can be incremented/decremented
  with arrow keys (Shift+arrow for 10x, Alt+arrow for 0.1x).
- **Add new rules** — click the `+` button to create a new rule
  targeting the current selector. Useful for testing styles before
  writing them in your codebase.
- **Toggle properties** — the checkbox next to each property enables
  or disables it without deleting. Use this to isolate which property
  is causing a visual problem.
- **Filter styles** — the filter input at the top of the Styles pane
  searches across all applied rules. Type `margin` to see every
  margin declaration affecting this element.

### Computed styles

The "Computed" tab shows the final resolved value of every CSS
property after the cascade, inheritance, and relative units are all
resolved. This is the ground truth — when the Styles pane has five
conflicting `font-size` declarations, Computed shows you which one
won and what the pixel value actually is.

- **Show all** — by default, only properties with non-default values
  are shown. Check "Show all" to see every inherited property.
- **Navigate to source** — click the arrow next to any computed value
  to jump to the rule that set it in the Styles pane.
- **Box model** — the visual box model diagram shows
  margin/border/padding/content dimensions. Hover over each zone to
  highlight it on the page. Click values to edit.

### Layout debugging (Grid and Flexbox)

Modern DevTools have dedicated overlays for CSS Grid and Flexbox that
make container layout visible:

- **Grid overlay** — in the Elements panel, grid containers show a
  badge. Click it to toggle a persistent overlay showing grid lines,
  track sizes, area names, and gap dimensions. The Layout pane (in
  the sidebar) lets you configure overlay appearance and toggle
  multiple grids simultaneously.
- **Flexbox overlay** — flexbox containers also show a badge.
  The overlay shows the flex direction, item sizing, and how free
  space is distributed. When items overflow or shrink unexpectedly,
  the overlay shows exactly which flex properties are responsible.
- **Container queries** — newer DevTools (Chrome 116+) show container
  query breakpoints and which container scope applies to a given
  element.

### Accessibility inspection

The Accessibility pane (in the Elements sidebar) shows:

- **Computed role and name** — what the element represents to
  assistive technology.
- **ARIA attributes** — both explicit and implicit.
- **Contrast ratio** — for text elements, whether the
  foreground/background combination meets WCAG AA or AAA.
- **Accessibility tree** — the full tree that screen readers navigate
  (not the DOM tree — elements with `aria-hidden`, `display: none`,
  etc. are excluded).

## Console

The Console is three things: an error log, a JavaScript REPL, and a
diagnostic output stream.

### Error and warning interpretation

Everything that goes wrong in the browser surfaces here:

- **JavaScript errors** — uncaught exceptions, with full stack traces
  linking back to source (or source-mapped source).
- **Network errors** — failed fetches, CORS violations, mixed content
  blocks. The error messages are specific: "blocked by CORS policy:
  No 'Access-Control-Allow-Origin' header" tells you the server
  response is missing a header, not that the request itself is wrong.
- **CSP violations** — Content Security Policy blocks, with the
  directive that fired and the resource that was blocked.
- **Deprecation warnings** — APIs that will break in future browser
  versions.
- **Security warnings** — mixed content, insecure form submissions,
  certificate issues.

### As a REPL

The Console is a full JavaScript runtime connected to the page:

- **`$0`** — reference to the currently selected element in the
  Elements panel. `$0.style.background = 'red'` highlights it.
  `$1` through `$4` are the previous selections.
- **`$(selector)`** — alias for `document.querySelector`.
  `$$('div.card')` returns all matching elements (not just the first).
- **`copy(object)`** — copies any object to the clipboard as JSON.
  `copy(performance.getEntries())` gives you all performance timing
  data in your clipboard.
- **`monitor(fn)`** — logs every call to a function with its
  arguments. `monitor(fetch)` shows you every fetch call the page
  makes.
- **`getEventListeners(element)`** — shows all event listeners
  attached to an element, including those added by frameworks.
- **Live expressions** — the eye icon at the top of the Console pins
  an expression that re-evaluates continuously. Pin
  `document.querySelectorAll('.loading').length` to watch loading
  states resolve in real time.

### Filtering and grouping

- **Log levels** — filter by Errors, Warnings, Info, Verbose.
  Default view hides Verbose.
- **Source filter** — filter by URL to see only messages from your
  code (hide framework noise).
- **`console.group()` / `console.groupEnd()`** — collapse related
  messages. `console.table(array)` renders tabular data. These are
  better than raw `console.log` when you need them, but the debugger
  is still better than either.

## Sources panel (JavaScript debugger)

The Sources panel is a full debugger with the same capabilities as an
IDE debugger — breakpoints, stepping, watch expressions, and scope
inspection — but running against code executing in the browser.

### Breakpoints

- **Line breakpoints** — click the line number gutter. Execution
  pauses before that line runs.
- **Conditional breakpoints** — right-click the gutter > "Add
  conditional breakpoint." Execution pauses only when the expression
  evaluates to true. Use this to break on the 47th iteration of a
  loop or when a specific user ID is in context.
- **Logpoints** — right-click > "Add logpoint." Emits a console
  message at that line without pausing. This is the `console.log`
  replacement that does not require modifying source or restarting.
- **DOM breakpoints** — set in the Elements panel (Break on subtree
  modification, attribute change, node removal). The debugger pauses
  in the Sources panel at the JavaScript line that caused the DOM
  mutation.
- **XHR/fetch breakpoints** — in the right sidebar under "XHR/fetch
  Breakpoints," add a URL substring. The debugger pauses whenever a
  request matching that substring is initiated. Use this to find which
  code triggers a specific API call.
- **Event listener breakpoints** — in the sidebar, expand "Event
  Listener Breakpoints" to break on categories (Mouse > click,
  Keyboard > keydown, Timer > setTimeout, etc.). This answers "what
  happens when I click this button?" without knowing which code
  handles it.
- **Exception breakpoints** — the pause icon in the top bar toggles
  "Pause on uncaught exceptions" and "Pause on caught exceptions."
  Caught-exception pausing is noisy in most frameworks but invaluable
  when debugging a swallowed error.

### Stepping

Once paused:

- **Step over** (F10) — execute the current line, move to next.
- **Step into** (F11) — descend into the function being called.
- **Step out** (Shift+F11) — run until the current function returns.
- **Continue** (F8) — resume until the next breakpoint.
- **Continue to here** — right-click any line while paused > "Continue
  to here." Executes without setting a permanent breakpoint.

### Scope and call stack

The right sidebar while paused shows:

- **Call Stack** — every function frame leading to the current pause
  point. Click any frame to see its local scope. "Async" separators
  show where async boundaries crossed (the promise chain or callback
  queue that connected the frames).
- **Scope** — Local, Closure, and Global scopes for the current
  frame. Every variable and its current value. Expand objects to
  inspect their properties. Edit values by double-clicking.
- **Watch** — expressions you define that are re-evaluated at every
  pause. Add `this.state`, `response.status`, or any expression
  relevant to what you are debugging.

### Source maps

Source maps connect the minified/bundled code the browser executes
back to the authored source. When source maps are available (they
load from the `//# sourceMappingURL` comment in the bundle), the
Sources panel shows your original files — TypeScript, JSX, SCSS,
whatever the build pipeline consumed.

- Source maps load automatically if the URL is reachable.
- If they do not load (e.g., production build without maps), you see
  only the minified bundle.
- "Enable JavaScript source maps" and "Enable CSS source maps" in
  DevTools settings must be checked (they are by default).
- For production debugging, some teams deploy source maps to a
  private URL and configure DevTools to load them via the
  "Source map" right-click option.

### Workspaces (filesystem mapping)

DevTools can map loaded resources back to files on your local
filesystem. When configured, edits in the Styles pane or Sources
panel persist directly to disk — you write CSS or fix JavaScript
directly in the browser and it saves to your source file.

Configure via Sources > Filesystem > "Add folder to workspace."
DevTools prompts for filesystem access and auto-maps files by URL
path.

## Network panel

The Network panel shows every request the page makes — XHR, fetch,
scripts, stylesheets, images, WebSocket frames, server-sent events.
This is the first place to look when the page is broken, slow, or
showing stale data.

### Reading the waterfall

Each request appears as a row with timing information rendered as a
horizontal bar:

- **Queueing** (gray) — the browser queued the request because the
  connection limit (6 per origin for HTTP/1.1) was reached.
- **Stalled/Blocking** (gray) — waiting for a connection to become
  available.
- **DNS Lookup** (teal) — resolving the hostname.
- **Initial connection** (orange) — TCP handshake.
- **SSL** (purple) — TLS negotiation.
- **Request sent** (green, thin) — time to send the request bytes.
- **Waiting (TTFB)** (green) — time to first byte from the server.
  This is your server response time. If this bar dominates, the
  problem is backend.
- **Content Download** (blue) — time to receive the response body.
  If this bar dominates, the response is large or the connection is
  slow.

### Filtering and searching

- **Type filter** — XHR, JS, CSS, Img, Media, Font, Doc, WS,
  Manifest. Click to show only that type. Most debugging starts with
  XHR/Fetch.
- **Text filter** — type a URL substring, method, status code, or
  header value.
- **Inverted filter** — prefix with `-` to exclude (e.g.,
  `-analytics` hides tracking requests).
- **Regex filter** — prefix with `/` for regex matching.
- **Status filter** — `status-code:404` or `status-code:500` to find
  failures.
- **Larger than / Smaller than** — `larger-than:1M` finds large
  responses.

### Inspecting individual requests

Click any request to see:

- **Headers** — request and response headers, parsed and raw. This is
  where you verify CORS headers, cache headers, auth tokens, and
  content types.
- **Preview** — rendered response (JSON formatted, images displayed,
  HTML rendered).
- **Response** — raw response body.
- **Timing** — per-request waterfall breakdown.
- **Initiator** — the call stack that triggered this request. Click
  the stack frames to jump to the Sources panel. This answers "what
  code made this request?"
- **Cookies** — request and response cookies with attributes (path,
  domain, secure, httpOnly, sameSite).

### Useful toggles

- **Disable cache** — forces the browser to re-fetch every resource
  on reload. Essential during development; without this, you are
  debugging stale cached assets.
- **Preserve log** — keeps the network log across page navigations.
  Without this, a redirect clears the log before you can see what
  happened. Enable when debugging redirect chains or form submissions.
- **Throttling** — simulate slow connections (Slow 3G, Fast 3G,
  custom profiles). Use this to test loading states, timeouts, and
  progressive enhancement.
- **Block request URL** — right-click > "Block request URL." The
  browser will fail this request on next load. Use to test error
  states or fallback behavior without modifying server code.
- **Replay XHR** — right-click > "Replay XHR." Re-sends the same
  request without reloading the page. Useful for retesting after
  server-side changes.

### Copy as cURL

Right-click any request > "Copy" > "Copy as cURL." This gives you a
command-line equivalent of the exact request the browser made —
headers, cookies, body, and all. Paste it into a terminal to
reproduce the request outside the browser, modify parameters, or
share with a backend engineer.

## Performance panel

The Performance panel records a trace of everything the browser does:
JavaScript execution, style recalculation, layout, paint, compositing,
and garbage collection. This is where you diagnose jank (dropped
frames), long tasks, and rendering bottlenecks.

### Recording a trace

1. Open the Performance panel.
2. Click the record button (or Cmd+E / Ctrl+E).
3. Perform the interaction you want to profile.
4. Stop recording.

The result is a timeline with multiple lanes:

### Reading the flame chart

- **Main thread** — the largest lane. Shows a flame chart where each
  bar is a function call. Width is time. Bars stacked below are
  functions called by the bar above. Long bars (>50ms) are long
  tasks — they block the main thread and cause jank.
- **Frames** — the frame rate row at the top. Green bars = frames
  rendered on time (60fps = 16.67ms budget). Red/orange bars = frames
  that missed their deadline.
- **Network** — requests overlaid on the timeline, showing when
  resources arrived relative to rendering.
- **Timings** — First Contentful Paint, Largest Contentful Paint,
  DOMContentLoaded, and other web vital markers.

### Identifying bottlenecks

- **Long yellow bars** — JavaScript taking too long. Click to see
  which function and its self-time vs. total-time.
- **Purple bars** — layout (reflow). Forced layout triggered by
  reading geometry properties (`offsetHeight`, `getBoundingClientRect`)
  after writing style properties. The tooltip says "Forced reflow is a
  likely performance bottleneck."
- **Green bars** — paint. Large or frequent paint events mean the
  browser is redrawing areas of the screen unnecessarily.
- **Gray bars** — system / idle. Not a problem.

### Bottom-up and call tree

Below the flame chart, the "Bottom-Up" tab shows which functions
consumed the most self-time (time spent in the function itself, not
in callees). This is the fastest way to find the hot function. "Call
Tree" shows the same data as a top-down tree from the entry point.

### Interaction to Next Paint (INP)

Chrome DevTools highlights interactions (clicks, key presses) in the
Timings lane and shows the total processing time for each. This maps
directly to the INP web vital — the responsiveness metric that Google
uses for Core Web Vitals scoring.

## Memory panel

The Memory panel diagnoses memory leaks and excessive allocation.
Three profiling modes:

### Heap snapshot

Captures the full object graph at a point in time. Shows every
JavaScript object, its size, what retains it (prevents garbage
collection), and the allocation site.

**Workflow for finding leaks:**

1. Take a snapshot (baseline).
2. Perform the action you suspect leaks (e.g., open and close a
   modal 10 times).
3. Take another snapshot.
4. Switch to "Comparison" view — shows objects allocated between
   snapshots that were not collected. These are your leaks.

**Retainer tree:** for any object, the retainer tree shows the chain
of references preventing garbage collection. The root of this chain
is the "why" of the leak — typically a stale event listener, a
closure over a variable that grew, or a detached DOM tree still
referenced by JavaScript.

### Allocation instrumentation on timeline

Records every allocation as it happens over time. The timeline shows
blue bars (allocations) and gray bars (deallocations). Bars that
remain blue were never collected — potential leaks. Click a blue bar
to see the specific objects and their allocation stack traces.

### Allocation sampling

Lower overhead than the timeline profiler. Samples allocation call
stacks periodically rather than recording every allocation. Useful
for long-running profiling sessions where the full timeline would be
too expensive.

### Common leak patterns

- **Detached DOM trees** — elements removed from the document but
  still referenced by JavaScript (e.g., saved in a variable, captured
  in a closure, stored in a `Map`). Filter the heap snapshot by
  "Detached" to find these.
- **Event listeners never removed** — `addEventListener` without a
  corresponding `removeEventListener` on unmount. Each listener holds
  a reference to its closure and everything the closure captures.
- **Growing Maps, Sets, or arrays** — collections used as caches
  without eviction. Each entry accumulates indefinitely.
- **Closures over large scope** — a small callback that captures a
  variable pointing at a large object prevents the large object from
  being collected for the lifetime of the callback.

## Application panel

The Application panel shows everything the browser stores locally:

### Storage inspection

- **Local Storage / Session Storage** — key-value pairs. View, edit,
  and delete entries directly.
- **Cookies** — per-domain, with all attributes visible (path, domain,
  expires, secure, httpOnly, sameSite, priority, size). Edit values
  directly. Delete individual cookies or clear all for a domain.
- **IndexedDB** — full database inspector. Expand databases, object
  stores, and indexes. Query and delete records.
- **Cache Storage** — service worker caches. See what resources are
  cached, their sizes, and delete individual entries.

### Service Workers

View registered service workers, their status (activated, waiting,
redundant), and their scope. Force update, unregister, or skip
waiting. The "Offline" checkbox simulates network disconnection to
test service worker cache behavior.

### Manifest

Web app manifest validation — shows icons, start URL, display mode,
and any validation errors that would prevent "Add to Home Screen"
installation.

## Responsive design mode

Triggered by the device icon in the DevTools toolbar (or
Cmd+Shift+M / Ctrl+Shift+M). Emulates different viewing conditions
without leaving your desktop browser.

### Viewport emulation

- **Preset devices** — iPhone, Pixel, iPad, and custom devices with
  correct viewport dimensions and device pixel ratios.
- **Custom dimensions** — drag the viewport handles or enter exact
  pixel values. Test specific breakpoints by setting the width to
  exactly your CSS breakpoint value.
- **Device pixel ratio** — simulate retina (2x, 3x) displays to test
  image resolution and sub-pixel rendering.

### How this differs from resizing the browser window

Responsive mode is not just a narrow window. It also:

- Sets the `User-Agent` string to the selected device (some servers
  serve different content based on UA).
- Emulates touch events (click becomes tap, `touchstart`/`touchend`
  fire instead of `mousedown`/`mouseup`).
- Sets the correct viewport meta tag behavior (`width=device-width`
  scaling).
- Simulates the device orientation sensor.

### Media query debugging

Chrome DevTools shows media query breakpoints as colored bars above
the viewport. Click a bar to snap to that viewport width. This shows
you exactly where your responsive breakpoints fire and in what order.

### Network throttling in responsive mode

The responsive toolbar includes throttling presets. Combine narrow
viewport (mobile) with slow network (3G) to test the actual mobile
experience — not just the layout, but the load performance and
interaction latency.

## Lighthouse (Audits)

Lighthouse runs automated audits against the current page:

- **Performance** — loading metrics (FCP, LCP, CLS, TBT), resource
  optimization opportunities, and diagnostics.
- **Accessibility** — automated checks for WCAG violations (color
  contrast, missing alt text, form labels, ARIA attributes).
- **Best Practices** — HTTPS, no vulnerable JavaScript libraries, no
  console errors, correct image aspect ratios.
- **SEO** — meta tags, crawlability, structured data.

Run via the "Lighthouse" tab in DevTools, or from the command line:

```sh
npx lighthouse https://localhost:3000 --view
```

Lighthouse scores are directional (they change between runs due to
network variability), but the specific recommendations are actionable.
Treat it as a checklist, not a grade.

## WebSocket and real-time inspection

For WebSocket connections, the Network panel shows the initial HTTP
upgrade request. Click it, then switch to the "Messages" tab to see
every frame sent and received over the WebSocket — both directions,
with timestamps and payload content.

For Server-Sent Events (EventSource), the "EventStream" tab shows
each event as it arrives.

For long-polling or streaming responses, the Network panel shows the
response body growing in real time.

## Chrome DevTools Protocol (CDP)

The DevTools GUI is built on top of a programmatic protocol — the
Chrome DevTools Protocol. This protocol exposes every capability
described on this page over a WebSocket connection, enabling
automation, remote debugging, and IDE integration.

### Practical uses

- **Remote debugging** — connect DevTools to a browser running on
  another machine, a mobile device (Chrome on Android via
  `chrome://inspect`), or a headless instance in CI.
- **Network interception in tests** — Playwright and Puppeteer use
  CDP to intercept network requests, mock API responses, and simulate
  offline conditions programmatically.
- **Performance automation** — collect Lighthouse or tracing data in
  CI to catch performance regressions before merge.
- **IDE integration** — VS Code's JavaScript debugger connects via
  CDP, which is why "Attach to Chrome" debug configurations work.

### Enabling remote debugging

```sh
# Launch Chrome with remote debugging enabled
# macOS:
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --remote-debugging-port=9222

# Linux:
google-chrome --remote-debugging-port=9222

# Connect from another DevTools instance:
# Open chrome://inspect in another Chrome window

# Connect from Playwright:
# browserType.connectOverCDP('http://localhost:9222')
```

### Other browsers

- **Firefox** — Remote Debugging Protocol, accessible via
  `about:debugging`. Firefox DevTools have unique capabilities:
  CSS Grid inspector was first-in-class, the Accessibility inspector
  is excellent, and the network panel shows security details inline.
- **Safari** — Web Inspector Protocol, accessible via the Develop
  menu (enable in Safari > Settings > Advanced > "Show features for
  web developers"). Required for debugging Safari-specific issues and
  iOS Safari via USB.
- **Edge** — uses Chromium DevTools (identical to Chrome) with
  additional Microsoft-specific features.

## Workflow patterns

### "What code handles this click?"

1. Elements panel > right-click the button > "Break on" > "Attribute
   modifications." OR:
2. Sources panel > Event Listener Breakpoints > Mouse > click.
3. Click the button. Debugger pauses at the handler.
4. Read the call stack to understand the full chain from event
   dispatch to side effect.

### "Why is this request failing?"

1. Network panel > filter to XHR/Fetch > find the red (failed)
   request.
2. Check the status code and response body (Headers/Response tabs).
3. Check the Console for a more detailed error (CORS, CSP, auth).
4. Click "Initiator" to see which code made the request.
5. Right-click > "Copy as cURL" > reproduce in terminal to isolate
   browser vs. server.

### "Why does this element look wrong?"

1. Right-click the element > Inspect.
2. Styles pane: look for overridden (struck-through) properties.
   The rule that wins is at the top.
3. Computed tab: check the final resolved value.
4. Toggle properties off/on to isolate which rule causes the
   problem.
5. Check the box model for unexpected margin/padding.
6. If it's a layout issue: check Grid/Flexbox overlays.

### "Why is the page slow?"

1. Performance panel > record the slow interaction.
2. Look at the Frames row — are frames being dropped?
3. Look at the Main thread flame chart — is there a long yellow
   (JavaScript) bar?
4. Bottom-Up tab: which function has the highest self-time?
5. If the issue is rendering (purple/green bars): check for forced
   reflows or excessive paint areas.
6. If the issue is network: check the Network lane for late-arriving
   resources blocking rendering.

### "Is this page leaking memory?"

1. Memory panel > take a heap snapshot (baseline).
2. Perform the suspected leaky action multiple times.
3. Take another heap snapshot.
4. Comparison view: what objects exist in snapshot 2 that did not
   exist in snapshot 1 and were never collected?
5. Check retainer trees to find why they survive garbage collection.

## Settings worth configuring

In DevTools settings (F1 or the gear icon):

- **Enable CSS source maps** — maps minified CSS back to SCSS/Less.
- **Enable JavaScript source maps** — maps bundled JS back to
  authored source.
- **Show user agent shadow DOM** — reveals browser-internal DOM
  (useful for styling native elements like `<input type="range">`).
- **Disable cache (while DevTools is open)** — under Network, but
  also accessible in settings. Ensures you always see fresh assets.
- **Auto-open DevTools for popups** — catches new windows/tabs with
  DevTools already attached.
- **Preserve log upon navigation** — system-wide default for the
  Network and Console "preserve log" checkbox.

## DevTools extensions

The built-in panels cover general web development. Framework-specific
and specialty extensions add dedicated panels that integrate with
the DevTools UI:

### Framework-specific

- **React Developer Tools** — adds "Components" and "Profiler" panels.
  The Components panel shows the React component tree (not the DOM
  tree), props, state, hooks values, and context for every mounted
  component. The Profiler records renders and shows which components
  re-rendered, why (state change, prop change, parent render), and
  how long each render took. Indispensable for diagnosing unnecessary
  re-renders and understanding component hierarchy.
- **Vue.js devtools** — adds a "Vue" panel with component tree,
  Vuex/Pinia state inspection, event timeline, routing visualization,
  and performance profiling. Shows computed properties, watchers, and
  the full reactive dependency graph.
- **Redux DevTools** — adds a panel for inspecting the Redux store
  (or any state management library that implements its protocol —
  Zustand, MobX-State-Tree, etc.). Shows every dispatched action, the
  state diff each action caused, and supports time-travel debugging
  (rewind to any previous state). The action replay capability alone
  justifies Redux's boilerplate in complex applications.
- **Angular DevTools** — component tree, change detection profiling,
  dependency injection graph, and router state.
- **Svelte DevTools** — component tree with props and state, event
  forwarding visualization.

### Specialty extensions

- **Clock manipulation** (e.g., "Tab Clock," "Change Timezone") —
  override `Date.now()`, `new Date()`, and the system timezone within
  the page. Essential for debugging time-dependent behavior:
  scheduling features, countdown timers, expiration logic,
  timezone-aware displays. Avoids modifying system time, which
  affects the entire machine.
- **Accessibility** — axe DevTools adds automated accessibility
  auditing beyond what Lighthouse provides, with guided remediation
  and rule explanations.
- **JSON formatters** — auto-format JSON responses viewed in the
  browser (useful when APIs return raw JSON without a frontend).
- **CORS debugging** — extensions that log detailed CORS negotiation
  information beyond what the Console shows.

### A note on extension trust

DevTools extensions have deep access to page content and network
traffic. Install only extensions from the framework developers
(React, Vue, Redux teams) or well-known open-source projects. Review
permissions before installing — a DevTools extension that requests
"Read and change all your data on all websites" has that access even
when DevTools is closed.

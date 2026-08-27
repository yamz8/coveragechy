import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Coverage.js" as Coverage

Panel {
  id: root

  moduleName: "yamz8.coveragechy"
  ipcTarget: "yamz8.coveragechy"
  // The panel's own IpcHandler below replaces the one Panel installs, so that
  // lookup() and copy() can join the stock open/close/toggle methods on the
  // same target instead of contending with them for it.
  manageIpc: false

  implicitWidth: barButton.implicitWidth
  implicitHeight: barButton.implicitHeight

  // A shield-check (U+F0565) from the Material Design Icons range, drawn from
  // Omarchy's configured Nerd Font so it stays monochrome and theme-tinted. It
  // reads as "covered", and no other installed widget uses it - pubmedchy
  // takes the book, icd10chy the tag, npichy the account-search mark.
  readonly property string coverageIcon: "󰕥"
  // Hard ceiling on how much of a response the shell will ever hold. Twelve
  // documents run to a few kilobytes, so 2 MiB is headroom that still stops a
  // hostile or hijacked endpoint from growing the shell process without
  // bound. Enforced in the fetch pipeline and re-checked here before anything
  // is parsed.
  readonly property int maxResponseBytes: 2 * 1024 * 1024
  readonly property int resultLimit: Coverage.clampResultLimit(setting("resultLimit", 8))
  // Titles run from two words to a full line, and only local results carry a
  // contractor, so rows size themselves and the list takes what they need up
  // to this ceiling.
  readonly property int maxResultsHeight: Style.space(430)
  readonly property int resultsHeight: results.length > 0 ? Math.min(resultList.contentHeight, root.maxResultsHeight) : 0
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property string query: ""
  property string scope: "national"
  property string resultsQuery: ""
  property string lastSignature: ""
  property var results: []
  property int totalCount: 0
  property int selectedIndex: 0
  property bool searching: false
  property bool aborting: false
  property string errorText: ""
  property string copiedId: ""

  function searchSignature() {
    return root.query.trim() + "\n" + root.scope;
  }

  function scopeLabel() {
    return Coverage.scopeLabel(root.scope);
  }

  function restoreDefaults() {
    root.scope = Coverage.scopeKey(root.setting("defaultScope", "national"));
  }

  function stopRequests() {
    if (searchProcess.running)
      searchProcess.running = false;
  }

  function clearSensitiveState() {
    root.aborting = true;
    root.stopRequests();
    root.query = "";
    root.resultsQuery = "";
    root.lastSignature = "";
    root.results = [];
    root.totalCount = 0;
    root.selectedIndex = 0;
    root.searching = false;
    root.errorText = "";
    root.copiedId = "";
  }

  function failWith(message) {
    root.searching = false;
    root.results = [];
    root.totalCount = 0;
    root.errorText = message;
  }

  // The request is a single JSON-RPC POST. curl is capped twice over:
  // --max-filesize stops the transfer at the limit even when the endpoint
  // declares no Content-Length, and the head -c stage holds the same bound on
  // curl builds that only honour a declared length. pipefail keeps curl's own
  // status as the pipeline status, so timeouts and transport failures still
  // reach onExited unchanged. The URL and the request body are passed as
  // positional arguments and after --, never spliced into the script text.
  function fetchCommand(body) {
    return ["bash", "-c", "set -o pipefail; " + "curl -fsS --max-time 20 --connect-timeout 5 " + "--max-filesize " + root.maxResponseBytes + " " + "-H 'Content-Type: application/json' " + "-H 'Accept: application/json, text/event-stream' " + "--user-agent coveragechy/1.0 --data-binary \"$2\" -- \"$1\" " + "| head -c " + root.maxResponseBytes, "coveragechy", Coverage.MCP_URL, body];
  }

  // A response that reaches the cap was truncated mid-flight and cannot be
  // valid JSON, so it is refused before any parser sees it.
  function refuseOversized(raw) {
    if (raw.length < root.maxResponseBytes)
      return false;

    root.failWith("The coverage service returned an oversized response — narrow the search and retry");
    return true;
  }

  function runSearch() {
    var body = Coverage.buildRequestBody(root.query, root.scope, root.resultLimit);
    if (!body) {
      searchField.forceActiveFocus();
      return;
    }
    if (root.searching)
      return;

    root.aborting = false;
    root.searching = true;
    root.errorText = "";
    root.copiedId = "";
    root.results = [];
    root.totalCount = 0;
    root.selectedIndex = 0;
    root.resultsQuery = root.query.trim();
    root.lastSignature = root.searchSignature();
    searchProcess.command = root.fetchCommand(body);
    searchProcess.running = true;
  }

  function applySearch(raw) {
    if (!root.opened || root.aborting)
      return;

    if (root.refuseOversized(raw))
      return;

    var parsed;
    try {
      parsed = Coverage.parseSearchResponse(raw, root.scope);
    } catch (error) {
      // The parser raises the service's own wording for a refusal, which is
      // more useful than a generic failure line.
      root.failWith("The coverage service could not answer — " + String(error.message || error));
      return;
    }

    root.totalCount = parsed.totalCount;
    root.results = parsed.documents;
    root.selectedIndex = 0;
    root.searching = false;
    root.errorText = parsed.documents.length === 0 ? "No coverage document matched — try a single word, or the other scope" : "";
  }

  function networkError(exitCode) {
    // 28 is curl's timeout. 63 is --max-filesize, 23 is curl failing to write
    // once head -c has closed the pipe, and 141 is that same stage seen as
    // SIGPIPE — all three mean the response outgrew the cap.
    if (exitCode === 28)
      return "The coverage service timed out — check the connection and retry";

    if (exitCode === 63 || exitCode === 23 || exitCode === 141)
      return "The coverage service returned an oversized response — narrow the search and retry";

    return "The coverage service is unavailable — check the connection and retry";
  }

  function refreshAfterScopeChange() {
    if (root.resultsQuery !== "" && !root.searching)
      root.runSearch();
  }

  function moveSelection(delta) {
    if (root.results.length === 0)
      return;

    root.selectedIndex = Math.max(0, Math.min(root.results.length - 1, root.selectedIndex + delta));
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
  }

  function selectedDocument() {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.results.length)
      return null;

    return root.results[root.selectedIndex];
  }

  // Copying is the primary action: the document id is what gets quoted in an
  // appeal, a policy note, or a prior-auth packet. The panel stays open so the
  // next document is one keystroke away. The id goes after -- as its own
  // argument, never through a shell.
  function copySelected() {
    var entry = root.selectedDocument();
    if (!entry || entry.displayId === "")
      return;

    Quickshell.execDetached(["wl-copy", "--", entry.displayId]);
    root.copiedId = entry.displayId;
  }

  function openSelected() {
    var entry = root.selectedDocument();
    if (!entry || entry.url === "")
      return;

    Quickshell.execDetached(["omarchy-launch-browser", entry.url]);
    root.close();
  }

  function openDatabase() {
    Quickshell.execDetached(["omarchy-launch-browser", Coverage.DATABASE_URL]);
    root.close();
  }

  function handleKey(event) {
    if (event.key === Qt.Key_Escape) {
      root.close();
      return true;
    }
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      root.switchPanel((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1);
      return true;
    }
    if (event.key === Qt.Key_Down) {
      root.moveSelection(1);
      return true;
    }
    if (event.key === Qt.Key_Up) {
      root.moveSelection(-1);
      return true;
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (root.searching || root.results.length === 0 || root.lastSignature !== root.searchSignature())
        root.runSearch();
      else if (event.modifiers & Qt.ControlModifier)
        root.openSelected();
      else
        root.copySelected();
      return true;
    }
    return false;
  }

  onOpenedChanged: {
    root.clearSensitiveState();
    root.restoreDefaults();
    if (root.opened)
      Qt.callLater(function () {
        searchField.forceActiveFocus();
      });
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void {
      root.open();
    }
    function close(): void {
      root.close();
    }
    function show(): void {
      root.open();
    }
    function hide(): void {
      root.close();
    }
    function toggle(): void {
      root.toggle();
    }
    // Look coverage up from a keybinding or a script:
    //   omarchy-shell yamz8.coveragechy lookup "acupuncture"
    // The text is written to the field rather than to root.query, because the
    // field owns the query once it has been typed in and would otherwise keep
    // showing the previous term.
    // The optional second argument picks the scope, so a keybinding can go
    // straight to the local determinations:
    //   omarchy-shell yamz8.coveragechy lookup "oxygen" local
    function lookup(query: string, scope: string): string {
      var normalized = String(query || "").trim();
      if (normalized === "")
        return "empty query";

      root.open();
      if (String(scope || "").trim() !== "")
        root.scope = Coverage.scopeKey(scope);

      searchField.text = normalized;
      Qt.callLater(function () {
        root.runSearch();
      });
      return "ok";
    }
    // Copy whatever is selected, so a keybinding can pair with lookup to put
    // the closest document id on the clipboard without touching the panel.
    function copy(): string {
      var entry = root.selectedDocument();
      if (!entry)
        return "no selection";

      root.copySelected();
      return entry.displayId;
    }
  }

  Process {
    id: searchProcess

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applySearch(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
    }
    onExited: function (exitCode) {
      if (root.aborting) {
        root.aborting = false;
        return;
      }
      if (exitCode !== 0 && root.opened)
        root.failWith(root.networkError(exitCode));
    }
  }

  BarIconButton {
    id: barButton

    anchors.fill: parent
    bar: root.bar
    text: root.coverageIcon
    tooltipText: "coveragechy · search Medicare coverage determinations"

    onPressed: function (mouseButton) {
      if (mouseButton === Qt.RightButton)
        root.openDatabase();
      else
        root.toggle();
    }
  }

  KeyboardPanel {
    id: popout

    anchorItem: barButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: searchField
    contentWidth: popout.fittedContentWidth(Style.space(720))
    contentHeight: popout.fittedContentHeight(content.implicitHeight, Style.space(820))

    Column {
      id: content

      width: parent.width
      spacing: Style.space(12)

      PanelHero {
        width: parent.width
        title: "coveragechy"
        meta: "Medicare coverage database — NCDs and LCDs"
        detail: "LIVE"
        foreground: root.foreground
        fontFamily: root.fontFamily

        iconComponent: Component {
          Text {
            text: root.coverageIcon
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }
        }

        trailingControl: Component {
          Button {
            text: "Open database"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: root.openDatabase()
          }
        }
      }

      PanelSeparator {
        width: parent.width
        foreground: root.foreground
      }

      Column {
        width: parent.width
        spacing: Style.space(8)

        PanelSectionHeader {
          width: parent.width
          text: "FIND A DETERMINATION"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Row {
          width: parent.width
          spacing: Style.spacing.sm

          TextField {
            id: searchField

            width: parent.width - searchButton.width - parent.spacing
            foreground: root.foreground
            placeholderText: "acupuncture, oxygen, glucose…"
            text: root.query
            onTextChanged: {
              root.query = text;
              root.copiedId = "";
            }
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function (event) {
              if (root.handleKey(event))
                event.accepted = true;
            }
          }

          Button {
            id: searchButton

            width: Math.max(Style.space(88), implicitWidth)
            text: root.searching ? "Looking…" : "Look up"
            bordered: true
            selected: true
            enabled: root.query.trim() !== "" && !root.searching
            opacity: enabled ? 1 : 0.45
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: root.runSearch()
          }
        }

        Text {
          width: parent.width
          // The keyword is matched close to literally, so a long phrase finds
          // nothing where its head word finds plenty.
          text: root.copiedId !== "" ? "Copied " + root.copiedId + " to the clipboard" : root.results.length > 0 && root.lastSignature !== root.searchSignature() ? "Query changed — press Enter or Look up to refresh these results" : "A short keyword works best — “glucose” finds what “continuous glucose monitor” misses"
          textFormat: Text.PlainText
          color: root.foreground
          opacity: root.copiedId !== "" ? 0.8 : root.results.length > 0 && root.lastSignature !== root.searchSignature() ? 0.72 : 0.42
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Item {
        width: parent.width
        implicitHeight: Math.max(scopeHeader.implicitHeight, scopeGroup.implicitHeight)

        PanelSectionHeader {
          id: scopeHeader

          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "SCOPE"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        ButtonGroup {
          id: scopeGroup

          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          options: [
            {
              value: "national",
              label: "National",
              tooltip: "NCDs — set by CMS for the whole country"
            },
            {
              value: "local",
              label: "Local",
              tooltip: "LCDs — set by the Medicare contractor for a region"
            }
          ]
          value: root.scope
          foreground: root.foreground
          background: "transparent"
          accent: root.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          focusable: false
          onChanged: function (value) {
            root.scope = value;
            root.refreshAfterScopeChange();
            searchField.forceActiveFocus();
          }
        }
      }

      PanelSeparator {
        width: parent.width
        foreground: root.foreground
      }

      Item {
        width: parent.width
        visible: root.results.length > 0
        implicitHeight: visible ? Math.max(resultsHeader.implicitHeight, resultsMeta.implicitHeight) : 0

        PanelSectionHeader {
          id: resultsHeader

          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "DETERMINATIONS"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Text {
          id: resultsMeta

          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: Coverage.formatCount(root.totalCount) + " matches  ·  showing " + root.results.length + "  ·  " + root.scopeLabel()
          textFormat: Text.PlainText
          color: root.foreground
          opacity: 0.48
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      ListView {
        id: resultList

        width: parent.width
        height: root.resultsHeight
        visible: root.results.length > 0
        clip: true
        model: root.results
        currentIndex: root.selectedIndex
        boundsBehavior: Flickable.StopAtBounds

        delegate: Rectangle {
          required property var modelData
          required property int index

          width: ListView.view.width
          height: body.implicitHeight + Style.space(22)
          radius: Style.cornerRadius / 2
          color: index === root.selectedIndex ? root.selectedBackground : "transparent"

          Rectangle {
            anchors {
              left: parent.left
              right: parent.right
              bottom: parent.bottom
            }
            visible: index < root.results.length - 1 && index !== root.selectedIndex
            height: 1
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
          }

          Column {
            id: body

            anchors {
              left: parent.left
              right: parent.right
              verticalCenter: parent.verticalCenter
              leftMargin: Style.spacing.rowPaddingX
              rightMargin: Style.spacing.rowPaddingX
            }
            spacing: Style.space(4)

            Item {
              width: parent.width
              implicitHeight: Math.max(idLabel.implicitHeight, titleLabel.implicitHeight)

              Text {
                id: idLabel

                anchors.left: parent.left
                anchors.top: parent.top
                width: Style.space(96)
                text: modelData.displayId
                textFormat: Text.PlainText
                color: index === root.selectedIndex ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                id: titleLabel

                anchors {
                  left: idLabel.right
                  right: parent.right
                  top: parent.top
                  leftMargin: Style.space(12)
                }
                text: modelData.title
                textFormat: Text.PlainText
                color: index === root.selectedIndex ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
              }
            }

            Text {
              width: parent.width
              // A national document is placed by manual chapter, a local one
              // by the contractor that issued it.
              text: modelData.type + (modelData.contractor !== "" ? "  ·  " + modelData.contractor : modelData.chapter !== "" ? "  ·  Chapter " + modelData.chapter : "") + (modelData.updated !== "" ? "  ·  Updated " + modelData.updated : "") + (modelData.effective !== "" ? "  ·  Effective " + modelData.effective : "") + (modelData.retired !== "" ? "  ·  RETIRED " + modelData.retired : "")
              textFormat: Text.PlainText
              color: index === root.selectedIndex ? root.selectedText : root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onEntered: root.selectedIndex = index
            onClicked: function (mouse) {
              root.selectedIndex = index;
              if (mouse.button === Qt.RightButton)
                root.openSelected();
              else
                root.copySelected();
            }
          }
        }
      }

      BorderSurface {
        id: emptyState

        width: parent.width
        visible: root.results.length === 0
        implicitHeight: visible ? Style.space(92) : 0
        color: Style.controlFill(false, false, root.foreground, root.accent)
        borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
        radius: Style.cornerRadius

        Column {
          width: parent.width - Style.space(40)
          anchors.centerIn: parent
          spacing: Style.space(5)

          Text {
            width: parent.width
            text: root.searching ? "Searching the coverage database…" : root.errorText !== "" ? "Couldn’t load determinations" : "Look up Medicare coverage"
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            width: parent.width
            text: root.searching ? "Searching " + root.scopeLabel() : root.errorText !== "" ? root.errorText : "Search national determinations, or the local ones a contractor issued"
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.48
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }
      }

      PanelSeparator {
        width: parent.width
        foreground: root.foreground
      }

      Item {
        width: parent.width
        implicitHeight: Math.max(safetyNote.implicitHeight, keyHints.implicitHeight)

        Text {
          id: safetyNote

          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Reference only  ·  no patient identifiers"
          textFormat: Text.PlainText
          color: root.foreground
          opacity: 0.46
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          id: keyHints

          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "↑↓ select  ·  Enter copy  ·  Ctrl+Enter open  ·  Esc close"
          textFormat: Text.PlainText
          color: root.foreground
          opacity: 0.32
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}

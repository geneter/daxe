/*
  This file is part of Daxe.

  Daxe is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Daxe is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with Daxe.  If not, see <http://www.gnu.org/licenses/>.
*/

part of daxe;

/**
 * Cursor and related operations (such as keyboard input and copy/paste)
 */
class Cursor {
  /// used to find the next or previous word position for ctrl arrow key events
  static final String wordDelimiters = "\n \t`~!@#^&*()-+=[{]}|;:'\",<.>/?";

  h.TextAreaElement _ta;
  h.SpanElement _caret;
  /// cursor selection position; use setSelection() to change
  Position selectionStart, selectionEnd;
  List<h.SpanElement> _spansSelection = new List<h.SpanElement>();
  List<DaxeNode> _selectedNodes = new List<DaxeNode>();
  /// true if the cursor is visible; use hide() and show() to change visibility
  bool visible;
  /// caret blinking delay
  static const Duration delay = const Duration(milliseconds: 700);
  /// caret blinking timer
  Timer _timer;
  HashMap<int, ActionFunction> _shortcuts;
  bool _donePaste;
  /// previous keyDown keyCode if event.metaKey was true
  int _metaKeyCode;
  /// shift active during keyPress
  bool _shiftOnKeyPress = false;
  Position _draggedSelectionStart = null;
  Position _draggedSelectionEnd = null;

  Cursor() {
    _ta = h.querySelector("#tacursor");
    _caret = h.querySelector("#caret");
    visible = true;
    _shortcuts = new HashMap<int, ActionFunction>();
    // FIXME: IE is always intercepting Ctrl-P
    _ta.onKeyUp.listen((h.KeyboardEvent event) => _keyUp(event));
    _ta.onKeyPress.listen((h.KeyboardEvent event) => _keyPress(event));
    _ta.onKeyDown.listen((h.KeyboardEvent event) => _keyDown(event));
    _ta.onBlur.listen((h.Event event) => _blur(event));
    _ta.onPaste.listen((h.ClipboardEvent e) {
      // check if current language might understand HTML.
      // If not, onPaste is not useful.
      List<String> hnames = ['p', 'ul', 'a'];
      for (String name in hnames)
        if (doc.cfg.elementReference(name) == null)
          return;
      h.DataTransfer data = null;
      try {
        // e.clipboardData does not work with IE
        // (not sure how to get window.clipboardData in pure Dart)
        data = e.clipboardData;
      } catch (ex) {
      }
      if (data != null) {
        // NOTE: data.types does not work in Firefox due to a bug in dart2js
        // (dart bug #27616)
        if (data.types is List<String>) {
          if (data.types.contains('text/html')) {
            pasteHTML(data.getData('text/html'), data.getData('text/plain'));
            e.preventDefault();
            _donePaste = true;
          } else if (data.types.contains('Files')) {
            _donePaste = pasteImage(data);
            if (_donePaste)
              e.preventDefault();
          }
        }
      }
    });
    _donePaste = false;
    _metaKeyCode = 0;
    newTimer();
  }

  /**
   * Defines the keyboard shortcuts with a map key name -> action.
   * This converts the map into the internal shortcuts property,
   * a map key code -> action used to handle events.
   */
  void setShortcuts(HashMap<String, ActionFunction> stringShortcuts) {
    HashMap<String, int> mappings = new HashMap<String, int>();
    mappings['A'] = h.KeyCode.A;
    mappings['B'] = h.KeyCode.B;
    mappings['C'] = h.KeyCode.C;
    mappings['D'] = h.KeyCode.D;
    mappings['E'] = h.KeyCode.E;
    mappings['F'] = h.KeyCode.F;
    mappings['G'] = h.KeyCode.G;
    mappings['H'] = h.KeyCode.H;
    mappings['I'] = h.KeyCode.I;
    mappings['J'] = h.KeyCode.J;
    mappings['K'] = h.KeyCode.K;
    mappings['L'] = h.KeyCode.L;
    mappings['M'] = h.KeyCode.M;
    mappings['N'] = h.KeyCode.N;
    mappings['O'] = h.KeyCode.O;
    mappings['P'] = h.KeyCode.P;
    mappings['Q'] = h.KeyCode.Q;
    mappings['R'] = h.KeyCode.R;
    mappings['S'] = h.KeyCode.S;
    mappings['T'] = h.KeyCode.T;
    mappings['U'] = h.KeyCode.U;
    mappings['V'] = h.KeyCode.V;
    mappings['W'] = h.KeyCode.W;
    mappings['X'] = h.KeyCode.X;
    mappings['Y'] = h.KeyCode.Y;
    mappings['Z'] = h.KeyCode.Z;
    for (String key in stringShortcuts.keys) {
      String up = key.toUpperCase();
      if (mappings[up] != null)
        _shortcuts[mappings[up]] = stringShortcuts[key];
    }
  }

  /**
   * Returns the document position for the mouse event, making sure
   * the position is inside a text node when it is possible.
   * Returns null if the mouse event is not in the document.
   */
  static Position findPosition(h.MouseEvent event) {
    Position pos1 = doc.findPosition(event.client.x, event.client.y);
    if (pos1 == null)
      return(null);
    pos1.moveInsideTextNodeIfPossible();
    assert(pos1.dn != null);
    return(pos1);
  }

  void _keyDown(h.KeyboardEvent event) {
    if (selectionStart == null)
      return;
    page.stopSelection();
    _donePaste = false;
    bool ctrl = event.ctrlKey || event.metaKey;
    bool shift = event.shiftKey;
    int keyCode = event.keyCode;
    if (event.metaKey) {
      _metaKeyCode = keyCode;
      _ta.value = ''; // remove content added for Safari
    } else
      _metaKeyCode = 0;
    _shiftOnKeyPress = false;
    if (keyCode == 91 || keyCode == 93) {
      // for Safari, command key down, put something in the field and select it
      // so that it will not beep and refuse to copy with a command-C
      _ta.value = ' ';
      _ta.select();
    } else if (ctrl && keyCode == h.KeyCode.X) {
      _ta.value = copy();
      _ta.select();
    } else if (ctrl && keyCode == h.KeyCode.C) {
      _ta.value = copy();
      _ta.select();
    } else if (keyCode == h.KeyCode.PAGE_DOWN) {
      pageDown();
    } else if (keyCode == h.KeyCode.PAGE_UP) {
      pageUp();
    } else if (keyCode == h.KeyCode.END) {
      lineEnd();
    } else if (keyCode == h.KeyCode.HOME) {
      lineStart();
    } else if (keyCode == h.KeyCode.LEFT) {
      if (shift)
        shiftLeft(ctrl);
      else
        left(ctrl);
    } else if (keyCode == h.KeyCode.UP) {
      up();
    } else if (keyCode == h.KeyCode.RIGHT) {
      if (shift)
        shiftRight(ctrl);
      else
        right(ctrl);
    } else if (keyCode == h.KeyCode.DOWN) {
      down();
    } else if (keyCode == h.KeyCode.BACKSPACE) {
      backspace();
    } else if (keyCode == h.KeyCode.DELETE) {
      suppr();
    } else if (keyCode == h.KeyCode.TAB && !ctrl) {
      tab(event, shift);
    } else if (ctrl && _shortcuts[keyCode] != null) {
      event.preventDefault();
      return;
    } else if (_ta.value != '') {
      // note: the first char will only be in ta.value in keyUp, this part
      // is only for long-pressed keys
      String v = _ta.value;
      _ta.value = '';
      doc.insertNewString(v, shift);
    } else {
      return;
    }
    newTimer();
  }

  void _keyPress(h.KeyboardEvent event) {
    // Save the state of shift when a key is pressed,
    // because shift might be released by the time of keyUp,
    // but should still be taken into account.
    if (event.shiftKey)
      _shiftOnKeyPress = true;
  }

  void _keyUp(h.KeyboardEvent event) {
    // NOTE: on MacOS, keyUp events are not fired when the command key is down
    // see: http://bitspushedaround.com/on-a-few-things-you-may-not-know-about-the-hellish-command-key-and-javascript-events/
    // 2 possible solutions: using keyPress, or keyUp for the command key
    // here keyUp for command key is used (event.metaKey is false because the key is released)
    // pb with this solution: cmd_down, Z, Z, cmd_up will only do a single cmd-Z
    bool ctrl = event.ctrlKey || event.metaKey;
    bool shift = event.shiftKey || _shiftOnKeyPress;
    _shiftOnKeyPress = false;
    int keyCode = event.keyCode;
    if ((keyCode == 91 || keyCode == 93) && _ta.value != '' && _metaKeyCode == 0) {
      _ta.value = ''; // remove content added for Safari
    }
    if ((keyCode == 224 || keyCode == 91 || keyCode == 93 || keyCode == 17) && _metaKeyCode != 0) {
      ctrl = true;
      keyCode = _metaKeyCode;
    }
    _metaKeyCode = 0;
    if (selectionStart == null)
      return;
    if (ctrl && !shift && keyCode == h.KeyCode.Z) { // Ctrl Z
      doc.undo();
      _ta.value = '';
    } else if (ctrl && ((!shift && keyCode == h.KeyCode.Y) ||
        (shift && keyCode == h.KeyCode.Z))) { // Ctrl-Y and Ctrl-Shift-Z
      doc.redo();
      _ta.value = '';
    } else if (ctrl && !shift && keyCode == h.KeyCode.X) { // Ctrl-X
      removeSelection();
      _ta.value = '';
      page.updateAfterPathChange();
    } else if (ctrl && !shift && keyCode == h.KeyCode.C) { // Ctrl-C
      _ta.value = '';
    } else if (ctrl && !shift && keyCode == h.KeyCode.V) { // Ctrl-V
      if (_donePaste) {
        return;
      }
      if (_ta.value != '') {
        try {
          pasteString(_ta.value);
        } on DaxeException catch(ex) {
          h.window.alert(ex.toString());
        }
        _ta.value = '';
        page.updateAfterPathChange();
      }
    } else if (ctrl && _shortcuts[keyCode] != null) {
      event.preventDefault();
      _shortcuts[keyCode]();
      page.updateAfterPathChange();
    } else if (_ta.value != '') {
      String v = _ta.value;
      _ta.value = '';
      doc.insertNewString(v, shift);
    } else {
      return;
    }
    newTimer();
  }

  void _blur(h.Event event) {
    hide();
  }

  /**
   * Action for the line start key.
   */
  void lineStart() {
    Point pt = selectionStart.positionOnScreen();
    if (pt == null)
      return;
    //pt.x = 0;
    // this does not work when blocks are used (it moves the cursor outside)
    DaxeNode dn = selectionStart.dn;
    if (dn == null)
      return;
    while (!dn.block && dn.parent != null)
      dn = dn.parent;
    h.Element hnode = dn.getHTMLNode();
    h.Rectangle rect = hnode.getBoundingClientRect();
    pt.x = rect.left + 1;
    pt.y += 5;
    Position pos = doc.findPosition(pt.x, pt.y);
    if (pos == null)
      return;
    if (pos != null) {
      moveTo(pos);
      page.updateAfterPathChange();
    }
  }

  /**
   * Action for the line end key.
   */
  void lineEnd() {
    Point pt = selectionStart.positionOnScreen();
    if (pt == null)
      return;
    //pt.x += 10000;
    // this does not work when blocks are used (it moves the cursor outside)
    DaxeNode dn = selectionStart.dn;
    if (dn == null)
      return;
    while (!dn.block && dn.parent != null)
      dn = dn.parent;
    h.Element hnode = dn.getHTMLNode();
    h.Rectangle rect = hnode.getBoundingClientRect();
    pt.x = rect.right - 2;
    pt.y += 5;
    Position pos = doc.findPosition(pt.x, pt.y);
    if (pos == null)
      return;
    if (pos != null) {
      moveTo(pos);
      page.updateAfterPathChange();
    }
  }

  /**
   * Action for the left arrow key.
   */
  void left(bool ctrl) {
    deSelect();
    if (ctrl)
      selectionStart = previousWordPosition(selectionStart);
    else
      selectionStart = previousCaretPosition(selectionStart);
    selectionEnd = new Position.clone(selectionStart);
    updateCaretPosition(true);
    page.updateAfterPathChange();
  }

  /**
   * Action for the right arrow key.
   */
  void right(bool ctrl) {
    Position end = new Position.clone(selectionEnd);
    if (ctrl)
      end = nextWordPosition(end);
    else
      end = nextCaretPosition(end);
    deSelect();
    selectionStart = new Position.clone(end);
    selectionEnd = new Position.clone(end);
    updateCaretPosition(true);
    page.updateAfterPathChange();
  }

  /**
   * Action for the up arrow key.
   */
  void up() {
    deSelect();
    Point pt = selectionStart.positionOnScreen();
    if (pt == null)
      return;
    Position pos2 = selectionStart;
    while (pos2 == selectionStart) {
      pt.y = pt.y - 7;
      pos2 = doc.findPosition(pt.x, pt.y);
      pos2.moveInsideTextNodeIfPossible();
    }
    if (pos2 != null) {
      selectionStart = pos2;
      selectionEnd = new Position.clone(selectionStart);
    }
    updateCaretPosition(true);
    page.updateAfterPathChange();
  }

  /**
   * Action for the down arrow key.
   */
  void down() {
    deSelect();
    Point pt = selectionStart.positionOnScreen();
    if (pt == null)
      return;
    Position pos2 = selectionStart;
    while (pos2 == selectionStart) {
      pt.y = pt.y + 14;
      pos2 = doc.findPosition(pt.x, pt.y);
      pos2.moveInsideTextNodeIfPossible();
    }
    if (pos2 != null) {
      selectionStart = pos2;
      selectionEnd = new Position.clone(selectionStart);
    }
    updateCaretPosition(true);
    page.updateAfterPathChange();
  }

  /**
   * Action for the shift + left arrow keys.
   */
  void shiftLeft(bool ctrl) {
    Position start = new Position.clone(selectionStart);
    if (ctrl)
      start = previousWordPosition(selectionStart);
    else
      start = previousCaretPosition(start);
    setSelection(start, selectionEnd);
  }

  /**
   * Action for the shift + right arrow keys.
   */
  void shiftRight(bool ctrl) {
    Position end = new Position.clone(selectionEnd);
    if (ctrl)
      end = nextWordPosition(end);
    else
      end = nextCaretPosition(end);
    setSelection(selectionStart, end);
  }

  /**
   * Action for the page up key.
   */
  void pageUp() {
    Point pt = selectionStart.positionOnScreen();
    if (pt == null)
      return;
    h.DivElement doc1 = h.document.getElementById('doc1');
    pt.y -= doc1.offsetHeight;
    Position pos = doc.findPosition(pt.x, pt.y);
    if (pos != null) {
      int initialScroll = doc1.scrollTop;
      moveTo(pos);
      doc1.scrollTop = initialScroll - doc1.offsetHeight;
      page.updateAfterPathChange();
    }
  }

  /**
   * Action for the page down key.
   */
  void pageDown() {
    Point pt = selectionStart.positionOnScreen();
    if (pt == null)
      return;
    h.DivElement doc1 = h.document.getElementById('doc1');
    pt.y += doc1.offsetHeight;
    Position pos = doc.findPosition(pt.x, pt.y);
    if (pos != null) {
      int initialScroll = doc1.scrollTop;
      moveTo(pos);
      doc1.scrollTop = initialScroll + doc1.offsetHeight;
      page.updateAfterPathChange();
    }
  }

  /**
   * Action for the backspace key.
   */
  void backspace() {
    if (selectionStart == selectionEnd) {
      DaxeNode dn = selectionStart.dn;
      int offset = selectionStart.dnOffset;
      if (dn is DNDocument && offset == 0)
        return;
      if (dn is DNText && offset == 0 && dn.parent is DNWItem &&
          dn.previousSibling == null && dn.parent.previousSibling == null) {
        // at the beginning of a WYSIWYG list
        DNWList.riseLevel();
        return;
      }
      // if the cursor is at a newline after a node with an automatic (not DOM) newline,
      // the user probably wants to remove the newline instead of the previous node.
      if (dn is DNText && offset == 0 && dn.nodeValue[0] == '\n' &&
          dn.previousSibling != null && dn.previousSibling.newlineAfter()) {
        removeChar(selectionStart);
        return;
      }
      // same thing for newlineInside
      if (dn is DNText && offset == 0 && dn.nodeValue[0] == '\n' &&
          dn.previousSibling == null && dn.parent.newlineInside()) {
        removeChar(selectionStart);
        return;
      }
      // if this is the beginning of a node with no delimiter, remove something
      // before instead of the node with no delimiter (unless it's empty)
      bool justMovedOutOfBlockWithNoDelimiter = false;
      while (dn != null && dn.noDelimiter && offset == 0 && dn.offsetLength > 0) {
        if (dn.noDelimiter && dn.block)
          justMovedOutOfBlockWithNoDelimiter = true;
        else
          justMovedOutOfBlockWithNoDelimiter = false;
        offset = dn.parent.offsetOf(dn);
        dn = dn.parent;
      }
      if (dn is! DNText && offset > 0) {
        DaxeNode prev = dn.childAtOffset(offset - 1);
        if (justMovedOutOfBlockWithNoDelimiter) {
        // if we're at the beginning of a paragraph and the previous element could
        // go inside, move all the previous elements that can inside the paragraph
          DaxeNode next = dn.childAtOffset(offset);
          assert(next.noDelimiter && next.block);
          if (prev.ref != next.ref && !prev.block &&
              ((prev is DNText && doc.cfg.canContainText(next.ref)) ||
                  (prev.ref != null && doc.cfg.isSubElement(next.ref, prev.ref)))) {
            _mergeBlockWithPreviousNodes(next);
            return;
          }
        }
        // if the previous node is a paragraph and the next node can move inside,
        // move all the following non-block nodes that can inside.
        if (prev.noDelimiter && prev.block && offset < dn.offsetLength) {
          DaxeNode next = dn.childAtOffset(offset);
          if (prev.ref != next.ref && !next.block &&
              ((next is DNText && doc.cfg.canContainText(prev.ref)) ||
              (next.ref != null && doc.cfg.isSubElement(prev.ref, next.ref)))) {
            _mergeBlockWithNextNodes(prev);
            return;
          }
        }
        // move inside previous node with no delimiter, unless 2 paragraphs need to be merged
        if (prev.noDelimiter && (!prev.block ||
            (offset == dn.offsetLength || dn.childAtOffset(offset).ref != prev.ref))) {
          dn = dn.childAtOffset(offset - 1);
          offset = dn.offsetLength;
          if (dn is! DNText && offset > 0)
            prev = dn.childAtOffset(offset - 1);
          else
            prev = null;
        }
      }
      // if this is the end of a node with no delimiter with a character inside,
      // do not remove the whole node, just the last character (except for text nodes)
      while ((dn is! DNText && dn.noDelimiter) && dn.offsetLength == offset &&
          dn.firstChild != null) {
        dn = dn.lastChild;
        offset = dn.offsetLength;
      }
      selectionStart = new Position(dn, offset);
      selectionEnd = new Position.clone(selectionStart);
      selectionStart.move(-1);
      removeChar(selectionStart);
      if (dn is DNText && offset > 1)
        return; // updateAfterPathChange is not needed in this case
    } else {
      removeSelection();
    }
    page.updateAfterPathChange();
  }

  /**
   * Action for the suppr key.
   */
  void suppr() {
    if (selectionStart == selectionEnd) {
      if (selectionStart.dn is DNDocument && selectionStart.dnOffset == selectionStart.dn.offsetLength)
        return;
      DaxeNode dn = selectionStart.dn;
      int offset = selectionStart.dnOffset;
      // if at the end, get out of nodes with no delimiter (unless empty)
      while (dn.noDelimiter && offset == dn.offsetLength && dn.offsetLength > 0) {
        offset = dn.parent.offsetOf(dn) + 1;
        dn = dn.parent;
      }
      if (dn is! DNText && offset > 0 && offset < dn.offsetLength) {
        DaxeNode next = dn.childAtOffset(offset);
        DaxeNode prev = dn.childAtOffset(offset-1);
        // if we're at the end of a paragraph and the next element could
        // go inside, move all the next elements that can inside the paragraph
        if (prev.noDelimiter && prev.block && next.ref != prev.ref && !next.block &&
            ((next is DNText && doc.cfg.canContainText(prev.ref)) ||
                (next.ref != null && doc.cfg.isSubElement(prev.ref, next.ref)))) {
          _mergeBlockWithNextNodes(prev);
          return;
        }
        // if the next node is a paragraph and the previous node can move inside,
        // move all the previous non-block nodes that can inside.
        if (next.noDelimiter && next.block && next.ref != prev.ref && !prev.block) {
          if ((prev is DNText && doc.cfg.canContainText(next.ref)) ||
              (prev.ref != null && doc.cfg.isSubElement(next.ref, prev.ref))) {
            _mergeBlockWithPreviousNodes(next);
            return;
          }
        }
      }
      // move inside next node with no delimiter unless 2 paragraphs need to be merged
      if (dn is! DNText && offset < dn.offsetLength) {
        DaxeNode next = dn.childAtOffset(offset);
        while (next != null && next.noDelimiter && (!next.block ||
            (offset == 0 || dn.childAtOffset(offset-1).ref != next.ref))) {
          dn = next;
          offset = 0;
          if (dn is! DNText && offset < dn.offsetLength)
            next = dn.childAtOffset(offset);
          else
            next = null;
        }
      }
      selectionStart = new Position(dn, offset);
      selectionEnd = new Position.clone(selectionStart);
      removeChar(selectionStart);
    } else {
      removeSelection();
    }
    page.updateAfterPathChange();
  }

  /**
   * Action for the tab key.
   * Moves the cursor to the next cell in a table.
   * Inserts spaces if spaces are preserved in the element
   * (without looking at parents).
   * If selection is empty, inserts 4 spaces.
   * If a text node is selected from the start or a new line,
   * indent the selected block.
   * Shift-tab can be used to unindent.
   */
  void tab(h.Event event, bool shift) {
    DaxeNode parent = selectionStart.dn;
    if (parent is DNText)
      parent = parent.parent;
    if (parent.nodeType != DaxeNode.ELEMENT_NODE)
      return;
    final String xmlspace = parent.getAttribute("xml:space");
    bool spacePreserve = (xmlspace == "preserve");
    if (!spacePreserve && parent.ref != null && xmlspace == null) {
      final List<x.Element> attributes = doc.cfg.elementAttributes(parent.ref);
      for (x.Element attref in attributes) {
        if (doc.cfg.attributeName(attref) == "space" &&
            doc.cfg.attributeNamespace(attref) == "http://www.w3.org/XML/1998/namespace") {
          final String defaut = doc.cfg.defaultAttributeValue(attref);
          if (defaut == "preserve")
            spacePreserve = true;
          else if (defaut == "default")
            spacePreserve = false;
          break;
        }
      }
    }
    if (!spacePreserve) {
      DNTD cell = null;
      while (parent != null) {
        if (parent is DNTD) {
          cell = parent;
          break;
        }
        parent = parent.parent;
      }
      if (cell != null) {
        // switch to next/previous cell if possible
        DNTD newCell = null;
        if (!shift) {
          if (cell.nextSibling is DNTD)
            newCell = cell.nextSibling;
          else if (cell.parent != null && cell.parent.nextSibling != null &&
              cell.parent.nextSibling.firstChild is DNTD)
            newCell = cell.parent.nextSibling.firstChild;
        } else {
          if (cell.previousSibling is DNTD)
            newCell = cell.previousSibling;
          else if (cell.parent != null && cell.parent.previousSibling != null &&
              cell.parent.previousSibling.lastChild is DNTD)
            newCell = cell.parent.previousSibling.lastChild;
        }
        if (newCell != null) {
          event.preventDefault();
          page.moveCursorTo(new Position(newCell, newCell.offsetLength));
          page.updateAfterPathChange();
        }
      }
      return;
    }
    if (selectionStart != selectionEnd) {
      // for a block of text
      if (selectionStart.dn is! DNText || selectionEnd.dn is! DNText ||
          selectionStart.dn != selectionEnd.dn)
        return;
      DaxeNode dn = selectionStart.dn;
      String s = dn.nodeValue;
      int offset1 = selectionStart.dnOffset;
      int offset2 = selectionEnd.dnOffset;
      if (offset1 != 0 && s[offset1 - 1] != '\n')
        return;
      String s2 = '';
      if (offset1 != 0)
        s2 = s.substring(0, offset1);
      int offset_newline = s.indexOf('\n', offset1);
      int offset = offset1;
      int newEnd = offset2;
      String tab = '    ';
      while (offset_newline != -1 && offset < offset2) {
        if (!shift) {
          s2 += tab + s.substring(offset, offset_newline + 1);
          newEnd += 4;
        } else if (s.startsWith(tab, offset)) {
          s2 += s.substring(offset + 4, offset_newline + 1);
          newEnd -= 4;
        } else {
          s2 += s.substring(offset, offset_newline + 1);
        }
        offset = offset_newline + 1;
        offset_newline = s.indexOf('\n', offset);
      }
      if (offset < offset2) {
        if (!shift) {
          s2 += tab + s.substring(offset);
          newEnd += 4;
        } else if (offset + 4 < offset2 && s.startsWith(tab, offset)) {
          s2 += s.substring(offset + 4);
          newEnd -= 4;
        } else {
          s2 += s.substring(offset);
        }
      } else {
        if (s.length > offset)
          s2 += s.substring(offset);
      }
      UndoableEdit edit = new UndoableEdit.compound(Strings.get('undo.insert_text'));
      Position dnpos = new Position(dn.parent, dn.parent.offsetOf(dn));
      edit.addSubEdit(new UndoableEdit.removeNode(dn));
      DNText dn2;
      if (dn.parent.needsSpecialDNText)
        dn2 = dn.parent.specialDNTextConstructor(s2);
      else
        dn2 = new DNText(s2);
      edit.addSubEdit(new UndoableEdit.insertNode(dnpos, dn2));
      doc.doNewEdit(edit);
      setSelection(new Position(dn2, offset1), new Position(dn2, newEnd));
      page.scrollToPosition(selectionStart);
      event.preventDefault();
      return;
    }
    
    if (shift)
      return;
    doc.insertString(selectionStart, "    ");
    event.preventDefault();
  }

  /**
   * Returns the document position for the caret following the given one.
   * The new position should be visually different, so it can advance
   * several times in the document when moving through nodes with
   * no visual delimiters.
   */
  Position nextCaretPosition(Position pos) {
    if (pos.dn is DNDocument && pos.dnOffset == pos.dn.offsetLength)
      return(pos);
    DaxeNode dn = pos.dn;
    int offset = pos.dnOffset;
    // when at the end, get out of non-block nodes with no delimiter
    while (dn != null && dn.noDelimiter && offset == dn.offsetLength && !dn.block) {
      offset = dn.parent.offsetOf(dn) + 1;
      dn = dn.parent;
    }
    // if the node at offset is a text or style, move inside
    DaxeNode nodeAtOffset;
    if (dn.firstChild != null && offset < dn.offsetLength)
      nodeAtOffset = dn.childAtOffset(offset);
    else
      nodeAtOffset = null;
    while (nodeAtOffset != null && nodeAtOffset.noDelimiter && !nodeAtOffset.block) {
      dn = nodeAtOffset;
      offset = 0;
      if (dn.firstChild != null && offset < dn.offsetLength)
        nodeAtOffset = dn.childAtOffset(offset);
      else
        nodeAtOffset = null;
    }

    // visible change of position
    // consecutive moves between blocks with no delimiter are not considered cursor moves
    bool noDelimiterBlockMove = false;
    if (offset == dn.offsetLength) {
      // get out of the node
      noDelimiterBlockMove = (dn.noDelimiter && dn.block);
      offset = dn.parent.offsetOf(dn) + 1;
      dn = dn.parent;
      while (noDelimiterBlockMove && dn.noDelimiter && dn.block && offset == dn.offsetLength) {
        // get out of other no delimiter block nodes
        offset = dn.parent.offsetOf(dn) + 1;
        dn = dn.parent;
      }
    } else if (dn is DNText) {
      // move in the text
      offset++;
    } else {
      // enter the node
      dn = dn.childAtOffset(offset);
      // when just entering a node, move to the first cursor position inside
      Position first = dn.firstCursorPositionInside();
      if (first != null) {
        dn = first.dn;
        offset = first.dnOffset;
        noDelimiterBlockMove = (dn.noDelimiter && dn.block);
      } else {
        // if there is none, move after this node
        offset = dn.parent.offsetOf(dn) + 1;
        dn = dn.parent;
      }
    }

    // move inside non-block nodes with no delimiter at current offset
    if (dn.firstChild != null && offset < dn.offsetLength)
      nodeAtOffset = dn.childAtOffset(offset);
    else
      nodeAtOffset = null;
    while (nodeAtOffset != null && nodeAtOffset.noDelimiter &&
        (!nodeAtOffset.block || noDelimiterBlockMove)) {
      dn = nodeAtOffset;
      offset = 0;
      if (dn.firstChild != null && offset < dn.offsetLength)
        nodeAtOffset = dn.childAtOffset(offset);
      else
        nodeAtOffset = null;
    }
    return(new Position(dn, offset));
  }

  /**
   * Returns the first caret position before the given one.
   */
  Position previousCaretPosition(Position pos) {
    if (pos.dn is DNDocument && pos.dnOffset == 0)
      return(pos);
    DaxeNode dn = pos.dn;
    int offset = pos.dnOffset;
    // when at the beginning, get out of non-block nodes with no delimiter
    while (dn != null && dn.noDelimiter && offset == 0 && !dn.block) {
      offset = dn.parent.offsetOf(dn);
      dn = dn.parent;
    }
    // if the node before is a text or style, move inside
    DaxeNode nodeBefore;
    if (dn.firstChild != null && offset > 0)
      nodeBefore = dn.childAtOffset(offset - 1);
    else
      nodeBefore = null;
    while (nodeBefore != null && nodeBefore.noDelimiter && !nodeBefore.block) {
      dn = nodeBefore;
      offset = dn.offsetLength;
      if (dn.firstChild != null && offset > 0)
        nodeBefore = dn.childAtOffset(offset - 1);
      else
        nodeBefore = null;
    }

    // visible change of position
    // consecutive moves between blocks with no delimiter are not considered cursor moves
    bool noDelimiterBlockMove = false;
    if (offset == 0) {
      // get out of the node
      noDelimiterBlockMove = (dn.noDelimiter && dn.block);
      offset = dn.parent.offsetOf(dn);
      dn = dn.parent;
      while (noDelimiterBlockMove && dn.noDelimiter && dn.block && offset == 0) {
        // get out of other no delimiter block nodes
        offset = dn.parent.offsetOf(dn);
        dn = dn.parent;
      }
    } else if (dn is DNText) {
      // move in the text
      offset--;
    } else {
      // enter the node
      dn = dn.childAtOffset(offset-1);
      offset = dn.offsetLength;
      // when just entering a node, move to the last cursor position inside
      Position last = dn.lastCursorPositionInside();
      if (last != null) {
        dn = last.dn;
        offset = last.dnOffset;
        noDelimiterBlockMove = (dn.noDelimiter && dn.block);
      } else {
        // if there is none, move before this node
        offset = dn.parent.offsetOf(dn);
        dn = dn.parent;
      }
    }

    // move inside non-block nodes with no delimiter before current offset
    if (dn.firstChild != null && offset > 0)
      nodeBefore = dn.childAtOffset(offset - 1);
    else
      nodeBefore = null;
    while (nodeBefore != null && nodeBefore.noDelimiter &&
        (!nodeBefore.block || noDelimiterBlockMove)) {
      dn = nodeBefore;
      offset = dn.offsetLength;
      if (dn.firstChild != null && offset > 0)
        nodeBefore = dn.childAtOffset(offset - 1);
      else
        nodeBefore = null;
    }
    return(new Position(dn, offset));
  }

  /**
   * Returns position one word to the left if possible,
   * otherwise returns the previous position.
   */
  Position previousWordPosition(Position pos) {
    if (pos.dn is DNText) {
      int offset = pos.dnOffset;
      String s = pos.dn.nodeValue;
      while (offset-1 >= 0 && wordDelimiters.contains(s[offset-1]))
        offset--;
      while (offset-1 >= 0 && !wordDelimiters.contains(s[offset-1]))
        offset--;
      if (offset != pos.dnOffset)
        return new Position(pos.dn, offset);
    }
    return previousCaretPosition(pos);
  }

  /**
   * Returns position one word to the right if possible,
   * otherwise returns the next position.
   */
  Position nextWordPosition(Position pos) {
    if (pos.dn is DNText) {
      int offset = pos.dnOffset;
      String s = pos.dn.nodeValue;
      while (offset < s.length && wordDelimiters.contains(s[offset]))
        offset++;
      while (offset < s.length && !wordDelimiters.contains(s[offset]))
        offset++;
      if (offset != pos.dnOffset)
        return new Position(pos.dn, offset);
    }
    return nextCaretPosition(pos);
  }

  /**
   * Update the caret position when selectionStart == selectionEnd
   */
  void updateCaretPosition(bool scroll) {
    if (selectionEnd != selectionStart)
      return;
    _caret.style.height = null;
    Point pt = selectionStart.positionOnScreen();
    if (pt == null) {
      visible = false;
    } else {
      visible = true;
      h.DivElement doc1 = h.document.getElementById('doc1');
      int doctop = doc1.offset.top;
      int docheight = doc1.offset.height;
      if (pt.y - doctop < 0 || pt.y - doctop > docheight) {
        if (scroll) {
          doc1.scrollTop += pt.y.toInt() - doctop;
          pt = selectionStart.positionOnScreen();
        } else {
          visible = false;
        }
      }
    }
    if (visible) {
      pt.x -= 0.5;
      _caret.style.visibility = 'visible';
      _caret.style.top = "${pt.y}px";
      _caret.style.left = "${pt.x}px";
      setCaretStyle();
      // move and focus the textarea
      _ta.style.top = "${pt.y}px";
      _ta.style.left = "${pt.x}px";
      // change height if inside a text node
      if (selectionStart.dn is DNText) {
        h.Element hn = selectionStart.dn.getHTMLNode();
        _caret.style.height = hn.getComputedStyle().fontSize;
      }
      _ta.focus();
    } else {
      _caret.style.visibility = 'hidden';
    }
  }

  /**
   * Sets the caret style (horizontal or vertical)
   */
  void setCaretStyle() {
    bool horizontal; // horizontal caret between block elements
    h.Element hparent = selectionStart.dn.getHTMLNode();
    bool parentBlock = _isBlock(hparent);
    if (parentBlock && selectionStart.dn.offsetLength > 0) {
      bool prevBlock;
      if (selectionStart.dnOffset > 0) {
        DaxeNode prev = selectionStart.dn.childAtOffset(selectionStart.dnOffset - 1);
        h.Element hprev = prev.getHTMLNode();
        prevBlock = _isBlock(hprev);
      } else {
        if (selectionStart.dn is DNWItem)
          prevBlock = false; // special case for the beginning of a WYSIWYG list item
        else
          prevBlock = true;
      }
      bool nextBlock;
      if (selectionStart.dnOffset < selectionStart.dn.offsetLength) {
        DaxeNode next = selectionStart.dn.childAtOffset(selectionStart.dnOffset);
        h.Element hnext = next.getHTMLNode();
        if (next is DNWItem && selectionStart.dnOffset == 0)
          nextBlock = false; // special case for the beginning of a WYSIWYG list
        else
          nextBlock = _isBlock(hnext);
      } else
        nextBlock = true;
      horizontal = prevBlock && nextBlock;
    } else
      horizontal = false;
    if (horizontal)
      _caret.classes.add('horizontal');
    else if (_caret.classes.contains('horizontal'))
      _caret.classes.remove('horizontal');
  }
  
  /**
   * Returns true if the given HTML element is a block element using
   * all horizontal space (this is used to set the caret style).
   */
  bool _isBlock(h.Element el) {
    return(el is h.DivElement || el is h.ParagraphElement || el is h.TableElement ||
      el is h.TableRowElement || el is h.UListElement || el is h.LIElement);
  }

  /**
   * Moves the caret to the given Position.
   */
  void moveTo(Position pos, {bool display:true}) {
    deSelect();
    selectionStart = new Position.clone(pos);
    selectionStart.moveInsideTextNodeIfPossible();
    selectionEnd = new Position.clone(selectionStart);
    if (display)
      updateCaretPosition(true);
    else
      hide();
  }

  /**
   * Hides the cursor.
   */
  void hide() {
    visible = false;
    _caret.style.visibility = 'hidden';
  }

  /**
   * Shows the cursor.
   */
  void show() {
    if (selectionStart != null && selectionStart == selectionEnd) {
      visible = true;
      _caret.style.visibility = 'visible';
    }
  }

  /**
   * Obtains the focus.
   */
  void focus() {
    if (visible)
      show();
    _ta.focus();
  }

  /**
   * Clears the hidden text area.
   */
  void clearField() {
    _ta.value = '';
  }

  /**
   * Changes the effective selection in the document, based
   * on desired start and end positions derived from mouse positions.
   * Starting with start and end, the selection is reduced to
   * avoid cutting elements, so that the selection can be cut.
   */
  setSelection(Position start, Position end) {
    if (selectionStart == start && selectionEnd == end) {
      if (start == end) {
        updateCaretPosition(false);
      }
      return;
    }
    deSelect();
    Position previousStart = selectionStart;
    selectionStart = new Position.clone(start);
    selectionEnd = new Position.clone(end);
    if (selectionStart == selectionEnd) {
      //update(selectionStart);
      updateCaretPosition(false);
      page.updateAfterPathChange();
      return;
    }
    if (selectionStart > selectionEnd) {
      Position temp = selectionStart;
      selectionStart = selectionEnd;
      selectionEnd = temp;
    }

    // fix selection start and end for styles (different positions look the same for the user)
    // and to keep only the elements entirely inside the selection
    // move the start and end positions out of text and style if possible
    // exception for hidden paragraphs and list items:
    //   selection is not extended when it is just the line
    while (selectionStart.dn.noDelimiter && selectionStart.dnOffset == 0 &&
        !((selectionStart.dn is DNHiddenP || selectionStart.dn is DNWItem) &&
        selectionEnd <= new Position(selectionStart.dn, selectionStart.dn.offsetLength))) {
      selectionStart = new Position(selectionStart.dn.parent,
          selectionStart.dn.parent.offsetOf(selectionStart.dn));
    }
    while (selectionStart.dn.noDelimiter &&
        selectionStart.dnOffset == selectionStart.dn.offsetLength) {
      selectionStart = new Position(selectionStart.dn.parent,
          selectionStart.dn.parent.offsetOf(selectionStart.dn) + 1);
    }
    while (selectionEnd.dn.noDelimiter &&
        selectionEnd.dnOffset == selectionEnd.dn.offsetLength) {
      selectionEnd = new Position(selectionEnd.dn.parent,
          selectionEnd.dn.parent.offsetOf(selectionEnd.dn) + 1);
    }
    while (selectionEnd.dn.noDelimiter && selectionEnd.dnOffset == 0 &&
        !((selectionEnd.dn is DNHiddenP || selectionEnd.dn is DNWItem) &&
        selectionEnd == selectionStart)) {
      selectionEnd = new Position(selectionEnd.dn.parent,
          selectionEnd.dn.parent.offsetOf(selectionEnd.dn));
    }
    // now move positions closer if possible
    if (selectionStart != selectionEnd) {
      if (selectionStart.dn.noDelimiter &&
          selectionStart.dnOffset == selectionStart.dn.offsetLength) {
        DaxeNode next = selectionStart.dn.nextNode();
        selectionStart = new Position(next.parent, next.parent.offsetOf(next));
      }
      if (selectionEnd.dn.noDelimiter &&
          selectionEnd.dnOffset == 0) {
        DaxeNode prev = selectionEnd.dn.previousNode();
        selectionEnd = new Position(prev.parent, prev.parent.offsetOf(prev) + 1);
      }
      bool cont;
      do {
        cont = false;
        if (selectionStart.dn is! DNText && selectionStart.dnOffset < selectionStart.dn.offsetLength) {
          DaxeNode next = selectionStart.dn.childAtOffset(selectionStart.dnOffset);
          if (new Position(selectionStart.dn, selectionStart.dnOffset + 1) > selectionEnd &&
              new Position(next, 0) < selectionEnd) {
            // next is not included and the end is after the beginning of next
            selectionStart = new Position(next, 0);
            cont = true;
          }
        }
      } while (cont);
      do {
        cont = false;
        if (selectionEnd.dn is! DNText && selectionEnd.dnOffset > 0) {
          DaxeNode prev = selectionEnd.dn.childAtOffset(selectionEnd.dnOffset - 1);
          if (new Position(selectionEnd.dn, selectionEnd.dnOffset - 1) < selectionStart &&
              new Position(prev, prev.offsetLength) > selectionStart) {
            // prev is not included and the start is before the end of prev
            selectionEnd = new Position(prev, prev.offsetLength);
            cont = true;
          }
        }
      } while (cont);
    }

    if (selectionStart.dn == selectionEnd.dn) {
      DaxeNode dn = selectionStart.dn;
      if (dn.nodeType == DaxeNode.TEXT_NODE) {
        _selectText(dn, selectionStart.dnOffset, selectionEnd.dnOffset);
      } else {
        for (int i = selectionStart.dnOffset; i < selectionEnd.dnOffset; i++) {
          DaxeNode child = dn.childAtOffset(i);
          child.setSelected(true);
          _selectedNodes.add(child);
        }
      }
    } else {
      DaxeNode startParent = selectionStart.dn;
      if (startParent.nodeType == DaxeNode.TEXT_NODE)
        startParent = startParent.parent;
      if (selectionEnd > new Position(startParent, startParent.offsetLength))
        selectionEnd = new Position(startParent, startParent.offsetLength);
      else {
        DaxeNode endParent = selectionEnd.dn;
        if (endParent.nodeType == DaxeNode.TEXT_NODE)
          endParent = endParent.parent;
        if (endParent != startParent) {
          while (endParent.parent != startParent) {
            endParent = endParent.parent;
          }
          selectionEnd = new Position(startParent, startParent.offsetOf(endParent));
        }
      }
      DaxeNode firstNode;
      if (selectionStart.dn.nodeType == DaxeNode.ELEMENT_NODE ||
          selectionStart.dn.nodeType == DaxeNode.DOCUMENT_NODE) {
        firstNode = selectionStart.dn.childAtOffset(selectionStart.dnOffset);
        if (firstNode != null) {
          Position p2 = new Position(selectionStart.dn, selectionStart.dnOffset + 1);
          if (selectionEnd >= p2) {
            firstNode.setSelected(true);
            _selectedNodes.add(firstNode);
          }
        }
      } else {
        firstNode = selectionStart.dn;
        _selectText(firstNode, selectionStart.dnOffset, firstNode.offsetLength);
      }
      if (firstNode != null) {
        for (DaxeNode next = firstNode.nextSibling; next != null; next = next.nextSibling) {
          Position p1 = new Position(next.parent, next.parent.offsetOf(next));
          if (p1 < selectionEnd) {
            if (next.nodeType != DaxeNode.TEXT_NODE ||
                selectionEnd >= new Position(next.parent, next.parent.offsetOf(next) + 1)) {
              next.setSelected(true);
              _selectedNodes.add(next);
            }
          } else
            break;
        }
      }
      if (selectionEnd.dn.nodeType == DaxeNode.TEXT_NODE) {
        _selectText(selectionEnd.dn, 0, selectionEnd.dnOffset);
      }
    }
    if (selectionEnd != selectionStart)
      hide();
    if (selectionStart != previousStart)
      page.updateAfterPathChange();
  }

  /**
   * Called by setSelection to add a span over characters to make them look selected.
   * Also sets up drag and drop on that span.
   */
  void _selectText(DaxeNode dn, int offset1, int offset2) {
    h.Element parent = dn.getHTMLNode();
    if (parent == null)
      return;
    h.Text n = parent.nodes.first;
    h.Node next = n.nextNode;
    hide();
    String s = dn.nodeValue;
    if (offset1 == 0) {
      n.remove();
    } else {
      n.text = s.substring(0, offset1);
    }
    h.SpanElement span = new h.SpanElement();
    _spansSelection.add(span);
    span.classes.add('selection');
    //span.appendText(s.substring(offset1, offset2));
    //see comment in deSelect
    span.append(new h.Text(s.substring(offset1, offset2)));
    if (next == null)
      parent.append(span);
    else
      parent.insertBefore(span, next);
    if (offset2 != s.length) {
      h.Text n3 = new h.Text(s.substring(offset2));
      if (span.nextNode == null)
        parent.append(n3);
      else
        parent.insertBefore(n3, span.nextNode);
    }
    setupDrag(span, null);
  }

  /**
   * Deselects anything selected and sets the selection end to
   * the selection start.
   */
  void deSelect() {
    for (h.SpanElement span in _spansSelection) {
      h.Element parent = span.parent;
      if (parent == null)
        continue;
      StringBuffer sb = new StringBuffer();
      for (h.Node hn in parent.nodes) {
        sb.write(hn.text);
      }
      parent.nodes.clear();
      // parent.appendText(sb.toString());
      // IE9 replaces \n by BR here when appendText is used
      // http://code.google.com/p/dart/issues/detail?id=11180
      parent.append(new h.Text(sb.toString()));
      selectionEnd = new Position.clone(selectionStart);
      visible = true;
    }
    _spansSelection.clear();
    for (DaxeNode dn in _selectedNodes) {
      dn.setSelected(false);
    }
    _selectedNodes.clear();
    /*
    This was an experiment to automatically remove empty style nodes.
    It is causing too many problems (for instance with undo, or text select).
    A better solution is to make invisible styles visible (see DNStyle).
    if (selectionStart != null && selectionStart == selectionEnd &&
        selectionStart.dn is DNStyle &&
        selectionStart.dn.firstChild == null) {
      // remove an empty style element
      DaxeNode toremove = selectionStart.dn;
      if (toremove.parent != null) { // otherwise it's already been removed
        // we can't do it now, because removing the node can cause text nodes to be merged,
        // and this could change the positions passed in a click
        Timer.run(() {
          print('removed $toremove');
          selectionStart = new Position(toremove.parent, toremove.parent.offsetOf(toremove));
          selectionEnd = new Position.clone(selectionStart);
          doc.removeNode(toremove);
          // TODO: automatically undo the creation and removal of the style element
        });
      }
    }
    */
  }

  /**
   * Starts a new timer for caret blinking.
   */
  void newTimer() {
    if (!visible)
      return;
    if (_timer != null)
      _timer.cancel();
    _caret.style.visibility = "visible";
    _timer = new Timer.periodic(delay, (Timer t) => caretBlink());
  }

  /**
   * Blinks the caret.
   */
  void caretBlink() {
    if (!visible)
      return;
    if (_caret.style.visibility == "hidden")
      _caret.style.visibility = "visible";
    else if (_caret.style.visibility == "visible")
      _caret.style.visibility = "hidden";
  }

  /**
   * Removes the first character or Daxe node coming after the cursor.
   */
  void removeChar(Position pos) {
    DaxeNode toremove;
    if (pos.dn.nodeType == DaxeNode.TEXT_NODE &&
        pos.dn.offsetLength < pos.dnOffset + 1 &&
        pos.dn.nextSibling != null) {
      // remove the next node
      DaxeNode current = pos.dn;
      DaxeNode next = current.nextSibling;
      while (next == null && current.parent != null) {
        current = current.parent;
        next = current.nextSibling;
      }
      toremove = next;
      if (toremove.nodeType == DaxeNode.TEXT_NODE && toremove.parent != null &&
          toremove.offsetLength == 1)
        toremove = toremove.parent;
    } else if (pos.dn.nodeType == DaxeNode.TEXT_NODE &&
        pos.dn.offsetLength < pos.dnOffset + 1 &&
        pos.dn.nextSibling == null) {
      // remove pos.dn's parent
      toremove = pos.dn;
      if (toremove.parent != null)
        toremove = toremove.parent;
      if (toremove.noDelimiter && toremove.block) {
        if (toremove.nextSibling.ref == toremove.ref) {
          // merge the blocks with no delimiter
          _mergeBlocks(toremove, toremove.nextSibling);
        } else {
          // remove something just after this character
          Position after = new Position.clone(pos);
          after.move(1);
          if (after > pos)
            removeChar(after);
        }
        return;
      }
    } else if (pos.dn.nodeType == DaxeNode.ELEMENT_NODE && pos.dn.offsetLength < pos.dnOffset + 1) {
      // remove pos.dn
      toremove = pos.dn;
      if (toremove.noDelimiter && toremove.block) {
        if (toremove.nextSibling != null && toremove.nextSibling.ref == toremove.ref) {
          // merge the blocks with no delimiter
          _mergeBlocks(toremove, toremove.nextSibling);
          return;
        }
      }
    } else if (pos.dn.nodeType == DaxeNode.ELEMENT_NODE ||
        pos.dn.nodeType == DaxeNode.DOCUMENT_NODE) {
      toremove = pos.dn.childAtOffset(pos.dnOffset);
      if (toremove.noDelimiter && toremove.block) {
        if (toremove.previousSibling != null && toremove.previousSibling.ref == toremove.ref) {
          // merge the blocks with no delimiter
          _mergeBlocks(toremove.previousSibling, toremove);
          return;
        } else if (toremove.offsetLength > 0) {
          // remove something just before this character
          Position before = new Position.clone(pos);
          before.move(-1);
          if (before < pos)
            removeChar(before);
          return;
        }
      }
      if (toremove == null) {
        h.window.alert("I'm sorry Dave, I'm afraid I can't do that.");
        return;
      }
    } else if (pos.dn.nodeType == DaxeNode.TEXT_NODE &&
        pos.dnOffset == 0 && pos.dn.offsetLength == 1 &&
        pos.dn.parent is DNStyle && pos.dn.parent.offsetLength == 1) {
      // remove the style node
      toremove = pos.dn.parent;
      while (toremove.parent is DNStyle && toremove.parent.offsetLength == 1)
        toremove = toremove.parent;
    } else {
      doc.removeString(pos, 1);
      // merge styles if possible
      EditAndNewPositions ep = DNStyle.mergeAt(selectionStart);
      if (ep != null) {
        doc.doNewEdit(ep.edit);
        doc.combineLastEdits(Strings.get('undo.remove_text'), 2);
        setSelection(ep.start, ep.end);
      }
      return;
    }
    if (toremove is DNWItem && toremove.parent.offsetLength == 1) {
      // remove the whole DNWList when the last DNWItem inside is removed
      toremove = toremove.parent;
    }
    if (!toremove.userCannotRemove) {
      doc.removeNode(toremove);
      // merge styles if possible
      EditAndNewPositions ep = DNStyle.mergeAt(selectionStart);
      if (ep != null) {
        doc.doNewEdit(ep.edit);
        doc.combineLastEdits(Strings.get('undo.remove_element'), 2);
        setSelection(ep.start, ep.end);
      }
    }
  }

  /**
   * Removes everything inside the current selection.
   */
  void removeSelection() {
    if (selectionStart == selectionEnd)
      return;
    Position start = new Position.clone(selectionStart);
    Position end = new Position.clone(selectionEnd);
    deSelect();
    if (start.dn is DNWList && start.dn == end.dn && start.dnOffset == 0 &&
        end.dnOffset == end.dn.offsetLength) {
      // all DNWItem will be removed, the whole DNWList must be removed instead
      doc.removeNode(start.dn);
    } else {
      doc.removeBetween(start, end);
      // merge styles if possible
      EditAndNewPositions ep = DNStyle.mergeAt(start);
      if (ep != null) {
        doc.doNewEdit(ep.edit);
        doc.combineLastEdits(Strings.get('undo.remove'), 2);
        setSelection(ep.start, ep.end);
      }
    }
  }

  /**
   * Refresh display
   */
  void refresh() {
    Position start = selectionStart;
    Position end = selectionEnd;
    selectionStart = null;
    selectionEnd = null;
    setSelection(start, end);
  }

  /**
   * Returns the current XML selection as a String.
   */
  String copy() {
    // TODO: add the namespace attributes
    StringBuffer sb = new StringBuffer();
    if (selectionStart.dn == selectionEnd.dn) {
      DaxeNode dn = selectionStart.dn;
      if (dn.nodeType == DaxeNode.TEXT_NODE) {
        sb.write(dn.nodeValue.substring(selectionStart.dnOffset, selectionEnd.dnOffset));
      } else {
        for (int i = selectionStart.dnOffset; i < selectionEnd.dnOffset; i++) {
          DaxeNode child = dn.childAtOffset(i);
          sb.write(child);
        }
      }
    } else {
      DaxeNode firstNode;
      if (selectionStart.dn.nodeType == DaxeNode.ELEMENT_NODE) {
        firstNode = selectionStart.dn.childAtOffset(selectionStart.dnOffset);
        Position p2 = new Position(selectionStart.dn, selectionStart.dnOffset + 1);
        if (selectionEnd >= p2) {
          sb.write(firstNode);
        }
      } else {
        firstNode = selectionStart.dn;
        sb.write(firstNode.nodeValue.substring(selectionStart.dnOffset));
      }
      for (DaxeNode next = firstNode.nextSibling; next != null; next = next.nextSibling) {
        Position p1 = new Position(next.parent, next.parent.offsetOf(next));
        if (p1 < selectionEnd) {
          if (next.nodeType != DaxeNode.TEXT_NODE ||
              selectionEnd >= new Position(next.parent, next.parent.offsetOf(next) + 1)) {
            sb.write(next);
            next.setSelected(true);
          }
        } else
          break;
      }
      if (selectionEnd.dn.nodeType == DaxeNode.TEXT_NODE) {
        sb.write(selectionEnd.dn.nodeValue.substring(0, selectionEnd.dnOffset));
      }
    }
    return(sb.toString());
  }

  /**
   * Parses the given String and pastes the XML or text at the current position.
   * Throws a [DaxeException] if it was not valid.
   */
  void pasteString(String s) {
    s = s.replaceAll(new RegExp(r'<\?xml[^?]*\?>'), ''); // remove doc decl
    x.Document tmpdoc;
    String parse = "<root";
    if (doc.cfg != null) {
      // add namespaces to a root element to get the right references later
      for (String namespace in doc.cfg.namespaceList()) {
        if (namespace != '') {
          String prefix = doc.cfg.namespacePrefix(namespace);
          String attname;
          if (prefix != null && prefix != '')
            attname = "xmlns:$prefix";
          else
            attname = "xmlns";
          parse += ' $attname="$namespace"';
        }
      }
    }
    parse += ">$s</root>";
    try {
      x.DOMParser dp = new x.DOMParser();
      tmpdoc = dp.parseFromString(parse);
    } on x.DOMException {
      // this is not XML, it is inserted as string if it is possible
      pasteText(s);
      return;
    }
    pasteXML(tmpdoc);
  }

  /**
   * Pastes the text at the current position (using hidden paragraphs if possible).
   * Throws a DaxeException if it was not valid.
   */
  void pasteText(String s) {
    DaxeNode parent = selectionStart.dn;
    if (parent is DNText)
      parent = parent.parent;
    if (parent == null)
      throw new DaxeException(Strings.get('insert.text_not_allowed'));
    x.Element hiddenp;
    if (parent.ref != null && doc.hiddenParaRefs != null)
      hiddenp = doc.cfg.findSubElement(parent.ref, doc.hiddenParaRefs);
    else
      hiddenp = null;
    bool parentWithText = parent.ref != null && doc.cfg.canContainText(parent.ref);
    bool problem = false;
    if (s.trim() != '') {
      if (parent.nodeType == DaxeNode.DOCUMENT_NODE)
        problem = true;
      else if (!parentWithText && hiddenp == null)
        problem = true;
    }
    if (problem)
      throw new DaxeException(Strings.get('insert.text_not_allowed'));

    // use hidden paragraphs instead of newlines if allowed at current position
    // also use hidden paragraphs if a paragraph is required to insert text
    bool useParagraphs = hiddenp != null && (s.contains('\n') || !parentWithText);
    if (!useParagraphs) {
      if (selectionStart == selectionEnd)
        doc.insertString(selectionStart, s);
      else {
        UndoableEdit edit = new UndoableEdit.compound(Strings.get('undo.paste'));
        // save and move start position so it keeps reliable for insert
        Position start = new Position.clone(selectionStart);
        while ((start.dn is DNText || start.dn is DNStyle) && start.dnOffset == 0)
          start = new Position(start.dn.parent, start.dn.parent.offsetOf(start.dn));
        if (start.dn is! DNText && start.dn.childAtOffset(start.dnOffset-1) is DNText) {
          DNText previous = start.dn.childAtOffset(start.dnOffset-1);
          start = new Position(previous, previous.offsetLength);
        }
        edit.addSubEdit(doc.removeBetweenEdit(selectionStart, selectionEnd));
        edit.addSubEdit(new UndoableEdit.insertString(start, s));
        doc.doNewEdit(edit);
      }
      return;
    }
    x.DOMImplementation domimpl = new x.DOMImplementationImpl();
    x.Document tmpdoc = domimpl.createDocument(null, null, null);
    x.Element root = tmpdoc.createElement('root');
    tmpdoc.appendChild(root);
    List<String> parts = s.split('\n');
    for (String part in parts) {
      x.Element p = tmpdoc.createElementNS(null, doc.cfg.elementName(hiddenp));
      if (part != '')
        p.appendChild(tmpdoc.createTextNode(part));
      root.appendChild(p);
    }
    pasteXML(tmpdoc);
  }

  /**
   * Pastes the XML (without the root element) at the current position.
   * Throws a DaxeException if it was not valid.
   */
  void pasteXML(x.Document tmpdoc) {
    x.Element root = tmpdoc.documentElement;
    if (root.firstChild != null && root.firstChild.nextSibling == null &&
        root.firstChild.nodeType == x.Node.TEXT_NODE) {
      pasteText(root.firstChild.nodeValue);
      return;
    }
    if (selectionStart == selectionEnd && doc.hiddenParaRefs != null &&
        selectionStart.dn is DNText && (selectionStart.dnOffset == 0 ||
        selectionStart.dnOffset == selectionStart.dn.offsetLength)) {
      DaxeNode parent = selectionStart.dn.parent;
      if (parent.parent != null && parent.parent.ref != null &&
          doc.hiddenParaRefs.contains(parent.ref)) {
        // at the beginning or end of a hidden paragraph: move paste position outside
        // if it helps to insert the first node
        // NOTE: we could generalize this behavior when the cursor is elsewhere
        //       and we could test more children
        if (!doc.cfg.isSubElementByName(parent.ref, root.firstChild.nodeName)) {
          if (doc.cfg.isSubElementByName(parent.parent.ref, root.firstChild.nodeName)) {
            if (selectionStart.dnOffset == 0)
              selectionStart = new Position(parent.parent,
                  parent.parent.offsetOf(parent));
            else
              selectionStart = new Position(parent.parent,
                  parent.parent.offsetOf(parent)+1);
            selectionEnd = new Position.clone(selectionStart);
          }
        }
      }
    }
    DaxeNode parent = selectionStart.dn;
    if (parent is DNText)
      parent = parent.parent;
    // to call fixLineBreaks(), we need a real DaxeNode for the "root", with the right ref
    DaxeNode dnRoot;
    if (parent.ref == null)
      dnRoot = new DNDocument();
    else
      dnRoot = NodeFactory.create(parent.ref);
    doc.cfg.addNamespaceAttributes(dnRoot);
    if (root.childNodes != null) {
      for (x.Node n in root.childNodes) {
        DaxeNode dn = NodeFactory.createFromNode(n, dnRoot);
        dnRoot.appendChild(dn);
      }
    }
    dnRoot.fixLineBreaks();
    if (doc.hiddenParaRefs != null) {
      // add or remove hidden paragraphs where necessary
      DNHiddenP.fixFragment(parent, dnRoot);
      doc.removeWhitespaceForHiddenParagraphs(dnRoot);
    }
    UndoableEdit edit = new UndoableEdit.compound(Strings.get('undo.paste'));

    // save and move positions so they keep reliable for insert and merge
    Position start = new Position.clone(selectionStart);
    while ((start.dn is DNText || start.dn is DNStyle) && start.dnOffset == 0)
      start = new Position(start.dn.parent, start.dn.parent.offsetOf(start.dn));
    while ((start.dn is DNText || start.dn is DNStyle) && start.dnOffset == start.dn.offsetLength)
      start = new Position(start.dn.parent, start.dn.parent.offsetOf(start.dn)+1);
    if (start.dn is! DNText && start.dn.childAtOffset(start.dnOffset-1) is DNText) {
      DNText previous = start.dn.childAtOffset(start.dnOffset-1);
      start = new Position(previous, previous.offsetLength);
    }
    Position end = new Position.clone(selectionEnd);
    while ((end.dn is DNText || end.dn is DNStyle) && end.dnOffset == 0)
      end = new Position(end.dn.parent, end.dn.parent.offsetOf(end.dn));
    while ((end.dn is DNText || end.dn is DNStyle) && end.dnOffset == end.dn.offsetLength)
      end = new Position(end.dn.parent, end.dn.parent.offsetOf(end.dn)+1);
    if (end.dn is! DNText && end.dn.childAtOffset(end.dnOffset) is DNText) {
      DNText next = end.dn.childAtOffset(end.dnOffset);
      end = new Position(next, 0);
    }
    end = new Position.rightOffsetPosition(end);

    if (selectionStart != selectionEnd)
      edit.addSubEdit(doc.removeBetweenEdit(selectionStart, selectionEnd));
    edit.addSubEdit(doc.insertChildrenEdit(dnRoot, start, checkValidity:true));
    doc.doNewEdit(edit);
    // merge styles if possible
    EditAndNewPositions ep = DNStyle.mergeAt(start);
    if (ep != null) {
      doc.doNewEdit(ep.edit);
      doc.combineLastEdits(Strings.get('undo.paste'), 2);
    }
    setSelection(end, end);
    ep = DNStyle.mergeAt(end);
    if (ep != null) {
      doc.doNewEdit(ep.edit);
      doc.combineLastEdits(Strings.get('undo.paste'), 2);
      setSelection(ep.end, ep.end);
    }
  }

  /**
   * Try to paste HTML, paste the plain alternative if that does not work.
   */
  void pasteHTML(String html, String plain) {
    // Let the browser and Dart parse and fix some of the syntax before trying to use it
    h.DivElement div = new h.DivElement();
    MyTreeSanitizer sanitizer = new MyTreeSanitizer();
    div.setInnerHtml(html, treeSanitizer:sanitizer);
    // XmlSerializer is deprecated; dart:js could be used if it is removed
    // from the dart API.
    // If it was removed from web browsers, we could not use browser sanitizing 
    // anymore, and would just parse the string directly.
    String fixed = (new h.XmlSerializer()).serializeToString(div);
    x.Document tmpdoc;
    try {
      x.DOMParser dp = new x.DOMParser();
      tmpdoc = dp.parseFromString(fixed);
      if (tmpdoc.documentElement.getAttribute('xmlns') != '') {
        tmpdoc.documentElement.removeAttribute('xmlns');
        _removeNamespace(tmpdoc.documentElement);
      }
      _cleanupHTML(tmpdoc.documentElement);
      // removeWhitespace needs the right references
      DaxeNode parent = selectionStart.dn;
      if (parent is DNText)
        parent = parent.parent;
      tmpdoc.documentElement.nodeName = parent.nodeName;
      tmpdoc.documentElement.namespaceURI = parent.namespaceURI;
      tmpdoc.documentElement.prefix = parent.prefix;
      tmpdoc.documentElement.localName = parent.localName;
      x.Element refGrandParent;
      if (parent.parent == null)
        refGrandParent = null;
      else
        refGrandParent = parent.parent.ref;
      doc._removeWhitespace(tmpdoc.documentElement, refGrandParent, false, true);
      try {
        pasteXML(tmpdoc);
        return;
      } on DaxeException catch(ex) {
        String errmsg = ex.toString();
        if (errmsg != Strings.get('insert.text_not_allowed') &&
            parent.ref != null && doc.cfg.canContainText(parent.ref)) {
          try {
            pasteText(plain);
            errmsg = Strings.get('cursor.pasting_xml_failed') +
                ' (' + errmsg + ')';
          } on DaxeException {
          }
        } else
          errmsg = Strings.get('insert.text_not_allowed');
        // see Blink bug:
        // https://code.google.com/p/chromium/issues/detail?id=299805
        // workaround: using a Timer
        Timer.run(()=>h.window.alert(errmsg));
      }
    } on x.DOMException {
      try {
        pasteText(plain);
      } on DaxeException catch(ex) {
        Timer.run(()=>h.window.alert(ex.toString()));
      }
    }
  }

  void _removeNamespace(x.Element el) {
    el.namespaceURI = null;
    for (x.Node n=el.firstChild; n!=null; n=n.nextSibling) {
      if (n.nodeType == x.Node.ELEMENT_NODE) {
        _removeNamespace(n);
      }
    }
  }

  /**
   * Try to cleanup the HTML, removing all style information and
   * some text processor crap.
   */
  void _cleanupHTML(x.Element el) {
    if (el.getAttribute('class') != '')
      el.removeAttribute('class');
    if (el.getAttribute('style') != '')
      el.removeAttribute('style');
    x.Node next;
    for (x.Node n=el.firstChild; n!=null; n=next) {
      next = n.nextSibling;
      if (n.nodeType == x.Node.ELEMENT_NODE) {
        x.Element en = n;
        if (n.prefix != null) {
          el.removeChild(n);
        } else {
          _cleanupHTML(n);
          String name = n.nodeName;
          bool replaceByChildren = false;
          if (name == 'center' || name == 'font') {
            replaceByChildren = true;
          } else if (name == 'b' || name == 'i') {
            if (n.firstChild == null)
              el.removeChild(n);
          } else if (name == 'span' || name == 'div') {
            if (n.firstChild == null) {
              el.removeChild(n);
            } else {
              replaceByChildren = true;
            }
          } else if (name == 'p' && n.firstChild != null &&
              (el.nodeName == 'li' || el.nodeName == 'td') &&
              (n.previousSibling == null ||
                (n.previousSibling.nodeType == x.Node.TEXT_NODE &&
                  n.previousSibling.previousSibling == null &&
                  n.previousSibling.nodeValue.trim() == '')) &&
              (n.nextSibling == null ||
                (n.nextSibling.nodeType == x.Node.TEXT_NODE &&
                  n.nextSibling.nextSibling == null &&
                  n.nextSibling.nodeValue.trim() == ''))) {
            // remove useless paragraphs in li and td
            replaceByChildren = true;
          } else if (name == 'img') {
            String src = en.getAttribute('src');
            // TODO: upload data images when possible
            if (src != null && !src.startsWith('data:'))
              en.setAttribute('src', src.split('/').last);
          } else if (name == 'a') {
            String href = en.getAttribute('href');
            if (href != null && href.startsWith('file://')) {
              String last = href.split('/').last;
              if (last.contains('#'))
                last = last.substring(last.indexOf('#'));
              en.setAttribute('href', last);
            }
          }
          if (replaceByChildren) {
            // replace element by its children
            x.Node first = n.firstChild;
            x.Node next2;
            for (x.Node n2=first; n2!=null; n2=next2) {
              next2 = n2.nextSibling;
              n.removeChild(n2);
              if (next == null)
                el.appendChild(n2);
              else
                el.insertBefore(n2, next);
            }
            el.removeChild(n);
            if (first != null)
              next = first;
          }
        }
      } else if (n.nodeType == x.Node.COMMENT_NODE) {
        el.removeChild(n);
      }
    }
    // normalize text
    for (x.Node n=el.firstChild; n!=null; n=n.nextSibling) {
      while (n.nodeType == x.Node.TEXT_NODE && n.nextSibling != null &&
          n.nextSibling.nodeType == x.Node.TEXT_NODE) {
        n.nodeValue = "${n.nodeValue}${n.nextSibling.nodeValue}";
        el.removeChild(n.nextSibling);
      }
    }
  }

  /**
   * Returns true if the image will probably be pasted.
   */
  bool pasteImage(h.DataTransfer data) {
    if (selectionStart == null)
      return false;
    DaxeNode parent = selectionStart.dn;
    if (parent is DNText)
      parent = parent.parent;
    if (parent.ref == null)
      return false;
    List<x.Element> childrenRefs = doc.cfg.subElements(parent.ref);
    x.Element imageRef = null;
    for (x.Element ref in childrenRefs) {
      String type = doc.cfg.elementDisplayType(ref);
      if (type == 'file' || type == 'fichier') {
        imageRef = ref;
        break;
      }
    }
    if (imageRef == null)
      return false;
    h.Blob blob = null;
    if (data.items != null) {
      // Chromium, pasted image (not a file)
      for (int i=0; i<data.items.length; i++) {
        // Interestingly, data.items[i] now crashes Dartium
        // (but it works with a more recent Chromium),
        // this might be dart bug 26435 which has been fixed recently...
        h.DataTransferItem item = data.items[i];
        if (item.type.indexOf('image') == 0) {
          blob = item.getAsFile();
          break;
        }
      }
    } else if (data.files != null) {
      // pasted file, might work with Firefox or IE
      for (int i=0; i<data.files.length; i++) {
        if (data.files[i].type.indexOf('image') == 0) {
          blob = data.files[i];
          break;
        }
      }
    }
    if (blob == null)
      return false;
    if (doc.saveURL == null) {
      // no server, use data: for src
      h.FileReader reader = new h.FileReader();
      reader.onLoad.listen((h.ProgressEvent e) {
        DNFile img = NodeFactory.create(imageRef);
        img.setSrc(reader.result);
        doc.insertNode(img, selectionStart);
      });
      reader.readAsDataUrl(blob);
    } else {
      // upload the image file
      try {
        _uploadAndCreateImage(blob, imageRef);
      } on DaxeException catch(ex) {
        h.window.alert(Strings.get('save.error') + ': ' + ex.message);
      }
    }
    return true;
  }

  Future _uploadAndCreateImage(h.Blob blob, x.Element imageRef) async {
    String type = blob.type;
    String filename;
    String dirURI = doc.filePath;
    dirURI = dirURI.substring(0, dirURI.lastIndexOf('/')+1);
    if (blob is h.File)
      filename = blob.name;
    else {
      String extension = type;
      if (extension.contains('/'))
        extension = extension.split('/').last;
      // read the directory to find a number to use in the file name
      Uri htmlUri = Uri.parse(h.window.location.toString());
      Uri docUri = Uri.parse(doc.filePath);
      List<String> segments = new List<String>.from(docUri.pathSegments);
      segments.removeLast();
      Uri openDir = docUri.replace(scheme:htmlUri.scheme, host:htmlUri.host,
          port:htmlUri.port, pathSegments:segments);
      List<DirectoryItem> items = await FileChooser.readDirectory(openDir);
      String baseName = 'pasted_image_';
      int newNumber = 1;
      for (DirectoryItem item in items) {
        if (item.type == DirectoryItemType.FILE && item.name.startsWith(baseName)) {
          String noExt = item.name;
          int ind = item.name.indexOf('.');
          if (ind != -1)
            noExt = item.name.substring(0, ind);
          String sNum = noExt.substring(baseName.length);
          int num;
          num = int.parse(sNum, onError: (String s) => null);
          if (num != null && num >= newNumber)
            newNumber = num + 1;
        }
      }
      filename = 'pasted_image_${newNumber}.' + extension;
    }
    String uri = dirURI + filename;
    try {
      await doc.uploadFile(uri, blob);
      DNFile img = NodeFactory.create(imageRef);
      img.setSrc(filename);
      doc.insertNode(img, selectionStart);
      return true;
    } catch (ex) {
      h.window.alert(ex.toString());
      return false;
    }
  }

  void _mergeBlocks(DaxeNode dn1, DaxeNode dn2) {
    UndoableEdit edit = new UndoableEdit.compound(Strings.get('undo.remove_text'));
    DaxeNode clone;
    Position clonep1 = new Position(dn2, 0);
    Position clonep2 = new Position(dn2, dn2.offsetLength);
    if (clonep2 > clonep1)
      clone = doc.cloneBetween(clonep1, clonep2);
    else
      clone = null;
    edit.addSubEdit(new UndoableEdit.removeNode(dn2));
    if (clone != null)
      edit.addSubEdit(doc.insertChildrenEdit(clone, new Position(dn1, dn1.offsetLength)));
    Position futureCursorPos;
    if (dn1.lastChild is DNText)
      futureCursorPos = new Position(dn1.lastChild, dn1.lastChild.offsetLength);
    else
      futureCursorPos = new Position(dn1, dn1.offsetLength);
    doc.doNewEdit(edit);
    page.moveCursorTo(futureCursorPos);
  }

  void _mergeBlockWithPreviousNodes(DaxeNode dn) {
    assert(dn.previousSibling != null);
    int offset = dn.parent.offsetOf(dn);
    UndoableEdit edit = new UndoableEdit.compound(Strings.get('undo.remove_text'));
    // clone the nodes that will move into the paragraph
    int startOffset = offset;
    bool withText = doc.cfg.canContainText(dn.ref);
    while (startOffset > 0) {
      DaxeNode child = dn.parent.childAtOffset(startOffset-1);
      if (child.block || (child is DNText && !withText) ||
          (child.ref != null && !doc.cfg.isSubElement(dn.ref, child.ref)))
        break;
      startOffset--;
    }
    Position pStart = new Position(dn.parent, startOffset);
    Position currentPos = new Position(dn.parent, offset);
    assert (pStart < currentPos);
    DaxeNode cloneLeft = doc.cloneCutBetween(dn.parent, pStart, currentPos);
    edit.addSubEdit(doc.removeBetweenEdit(pStart, currentPos));
    edit.addSubEdit(doc.insertChildrenEdit(cloneLeft, new Position(dn, 0)));
    Position futureCursorPos = new Position(dn, 0);
    futureCursorPos.moveInsideTextNodeIfPossible();
    futureCursorPos = new Position.rightOffsetPosition(futureCursorPos);
    doc.doNewEdit(edit);
    moveTo(futureCursorPos);
    page.updateAfterPathChange();
    return;
  }

  void _mergeBlockWithNextNodes(DaxeNode dn) {
    assert(dn.nextSibling != null);
    int offset = dn.parent.offsetOf(dn.nextSibling);
    UndoableEdit edit = new UndoableEdit.compound(Strings.get('undo.remove_text'));
    // clone the nodes that will move into the paragraph
    int endOffset = offset;
    bool withText = doc.cfg.canContainText(dn.ref);
    while (endOffset < dn.parent.offsetLength) {
      DaxeNode child = dn.parent.childAtOffset(endOffset);
      if (child.block || (child is DNText && !withText) ||
          (child.ref != null && !doc.cfg.isSubElement(dn.ref, child.ref)))
        break;
      endOffset++;
    }
    Position pEnd = new Position(dn.parent, endOffset);
    Position currentPos = new Position(dn.parent, offset);
    assert (currentPos < pEnd);
    DaxeNode cloneRight = doc.cloneCutBetween(dn.parent, currentPos, pEnd);
    edit.addSubEdit(doc.removeBetweenEdit(currentPos, pEnd));
    edit.addSubEdit(doc.insertChildrenEdit(cloneRight, new Position(dn, dn.offsetLength)));
    Position futureCursorPos = new Position(dn, dn.offsetLength);
    futureCursorPos.moveInsideTextNodeIfPossible();
    futureCursorPos = new Position.leftOffsetPosition(futureCursorPos);
    doc.doNewEdit(edit);
    moveTo(futureCursorPos);
    page.updateAfterPathChange();
    return;
  }

  /**
   * Copies the current selection to the clipboard when the browser allows it.
   * Otherwise display a message suggesting to use Ctrl-C.
   */
  void clipboardCopy() {
    if (selectionStart == null || selectionStart == selectionEnd)
      return;
    _ta.value = copy();
    _ta.select();
    bool success;
    try {
      success = h.document.execCommand('copy', false, null);
    } catch(ex) {
      success = false;
    }
    _ta.value = '';
    if (!success) {
      h.window.alert(Strings.get('menu.copy_with_keyboard'));
    }
  }

  /**
   * Copies the current selection to the clipboard when the browser allows it.
   * Otherwise display a message suggesting to use Ctrl-C.
   */
  void clipboardCut() {
    if (selectionStart == null || selectionStart == selectionEnd)
      return;
    _ta.value = copy();
    _ta.select();
    bool success;
    try {
      success = h.document.execCommand('cut', false, null);
    } catch(ex) {
      success = false;
    }
    _ta.value = '';
    if (success) {
      removeSelection();
      page.updateAfterPathChange();
    } else {
      h.window.alert(Strings.get('menu.cut_with_keyboard'));
    }
  }
  
  /**
   * Makes the HTML element draggable. If a DaxeNode is specified,
   * the HTML element represents it and the DaxeNode will be dragged.
   * If the DaxeNode is null, the current selection will be used instead.
   */
  void setupDrag(h.Element hel, DaxeNode dn) {
    hel.draggable = true;
    hel.onDragStart.listen((h.MouseEvent e) {
      e.dataTransfer.effectAllowed = 'copyMove';
      String data;
      if (selectionStart != null && selectionEnd > selectionStart &&
          (dn == null ||
            (selectionStart <= new Position(dn.parent, dn.parent.offsetOf(dn)) &&
            selectionEnd >= new Position(dn.parent, dn.parent.offsetOf(dn)+1)))) {
        data = copy();
      } else if (dn != null) {
        data = dn.toString();
        page.selectNode(dn);
        try {
          // setDragImage is not supported by Internet Explorer
          e.dataTransfer.setDragImage(dn.getHTMLNode(), 0, 0);
        } catch (ex) {
        }
      } else {
        return;
      }
      _draggedSelectionStart = selectionStart;
      _draggedSelectionEnd = selectionEnd;
      e.dataTransfer.setData('text', data); // not 'text/plain' because of IE11
    });
    hel.onDragEnd.listen((h.MouseEvent e) {
      _draggedSelectionStart = null;
      _draggedSelectionEnd = null;
    });
  }
  
  /**
   * Handles the effects of a drag and drop.
   * [pos] is the drop position in the document.
   * [data] is serialized XML or text (binary data or HTML are not handled).
   * [dropEffect] can be 'copy' or 'move'.
   */
  void drop(Position pos, String data, String dropEffect) {
    bool combine = false;
    if (_draggedSelectionStart != null && dropEffect == 'move') {
      if (pos >= _draggedSelectionStart && pos <= _draggedSelectionEnd)
        return;
      if (pos < _draggedSelectionStart)
        pos = new Position.leftOffsetPosition(pos);
      else
        pos = new Position.rightOffsetPosition(pos);
      setSelection(_draggedSelectionStart, _draggedSelectionEnd);
      removeSelection();
      // UndoableEdit._insert assumes the position is a NodeOffsetPosition
      pos = new Position.nodeOffsetPosition(pos);
      combine = true;
    }
    moveTo(pos);
    try {
      pasteString(data);
    } on DaxeException catch(ex) {
      bool error = true;
      // when dropping inside a table cell or list item,
      // try to drop as a table row or list item, before or after current pos.
      if (pos.dn is DNText && (pos.dnOffset == 0 || pos.dnOffset == pos.dn.offsetLength)) {
        // move out of text nodes
        DaxeNode dn = pos.dn;
        if (pos.dnOffset == 0)
          pos = new Position(dn.parent, dn.parent.offsetOf(dn));
        else
          pos = new Position(dn.parent, dn.parent.offsetOf(dn) + 1);
      }
      if (pos.dnOffset == 0 || pos.dnOffset == pos.dn.offsetLength) {
        DaxeNode dn = pos.dn;
        h.Element hel = dn.getHTMLNode();
        if (hel is h.TableRowElement || hel is h.TableCellElement || hel is h.LIElement) {
          if (pos.dnOffset == 0)
            pos = new Position(dn.parent, dn.parent.offsetOf(dn));
          else
            pos = new Position(dn.parent, dn.parent.offsetOf(dn) + 1);
        }
        if (hel is h.TableCellElement) {
          dn = pos.dn;
          if (pos.dnOffset == 0)
            pos = new Position(dn.parent, dn.parent.offsetOf(dn));
          else if (pos.dnOffset == dn.offsetLength)
            pos = new Position(dn.parent, dn.parent.offsetOf(dn) + 1);
        }
        moveTo(pos);
        try {
          pasteString(data);
          error = false;
        } on DaxeException {
        }
      }
      if (error) {
        h.window.alert(ex.toString());
        if (combine) {
          combine = false;
          doc.undo();
        }
      }
    }
    if (combine)
      doc.combineLastEdits(Strings.get('undo.drag_and_drop'), 2);
  }
}

class LaxUriPolicy implements h.UriPolicy {
  @override
  bool allowsUri(String uri) => true;
}

/**
 * We need a custom tree sanitizer because Dart's sanitizer removes an entire element content
 * when it is not valid. This sanitizer preserves the children in such a case,
 * which is standard behavior for HTML.
 */
class MyTreeSanitizer implements h.NodeTreeSanitizer {
  h.NodeValidator validator;

  MyTreeSanitizer() {
    h.UriPolicy policy = new LaxUriPolicy();
    validator = new h.NodeValidatorBuilder.common()
          ..allowImages(policy)
          ..allowNavigation(policy);
    // NOTE: we could allow inline style with allowInlineStyles(),
    // but then we will have to clean that up in cleanupHTML().
  }

  void sanitizeTree(h.Node node) {
    h.Node next;
    for (h.Node n=node.firstChild; n != null; n = next) {
      next = n.nextNode;
      if (n.nodeType == h.Node.ELEMENT_NODE) {
        h.Element ne = (n as h.Element);
        if (!validator.allowsElement(ne)) {
          // replace element by its children, except for <style> and <script>
          if (n.nodeName == 'STYLE' || n.nodeName == 'SCRIPT') {
            n.remove();
          } else {
            h.Node first = n.firstChild;
            h.Node next2;
            for (h.Node n2=first; n2!=null; n2=next2) {
              next2 = n2.nextNode;
              n2.remove();
              if (next == null)
                node.append(n2);
              else
                node.insertBefore(n2, next);
            }
            n.remove();
            if (first != null)
              next = first;
          }
        } else {
          Map<String, String> attributes = ne.attributes;
          attributes.forEach((String name, String value) {
            if (!validator.allowsAttribute(ne, name, value))
              ne.attributes.remove(name);
          });
          sanitizeTree(ne);
        }
      }
    }
  }
}

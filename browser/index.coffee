$ = require 'dom-fork'
_ = require 'lodash-fork'

ELEMENT_NODE = 1
ATTRIBUTE_NODE = 2
TEXT_NODE = 3
COMMENT_NODE = 8
DOCUMENT_NODE = 9
DOCUMENT_TYPE_NODE = 10
DOCUMENT_FRAGMENT_NODE = 11

regexSpace = new RegExp _.regexp_s
require 'debug-fork'
debug = global.debug 'ace:dom'

visitText = do ->
  inRange = false

  visit = (visitNode, start, end, fn) ->
    if visitNode.nodeType is TEXT_NODE
      return ret if ret = fn visitNode if (start._inRange ||= visitNode is start['container'])
    else
      children = visitNode.childNodes
      `var i = visitNode === start['container'] ? (start._inRange=true, start['offset']) : 0`
      iE = if visitNode is end['container'] then end['offset'] else children.length

      while i < iE
        return ret if ret = visit children[i], start, end, fn
        ++i

    visitNode is endPoint['container']

  (visitNode, start, end, fn) ->
    inRange = false
    visit visitNode, start, end, fn

visitTextForwardFn = do ->
  inRange = false

  visit = (visitNode, start, endFn, visitFn) ->
    if visitNode.nodeType is TEXT_NODE
      return ret if ret = visitFn visitNode if (inRange ||= visitNode is start['container'])
    else
      children = visitNode.childNodes
      `var i = visitNode === start['container'] ? (inRange=true, start['offset']) : 0`
      iE = children.length

      while i < iE
        node = children[i]
        return ret if ret = endFn node, visitNode, i if inRange
        return ret if ret = visit children[i], start, endFn, visitFn
        ++i
    return

  (visitNode, start, endFn, visitFn) ->
    inRange = false
    visit visitNode, start, endFn, visitFn

visitTextBackwardFn = do ->
  inRange = false

  visit = (visitNode, start, endFn, visitFn) ->
    if visitNode.nodeType is TEXT_NODE
      return ret if ret = visitFn visitNode if (inRange ||= visitNode is start['container'])
    else
      children = visitNode.childNodes
      `var i = -1 + (visitNode === start['container'] ? (inRange=true, start['offset']) : children.length)`

      while i >= 0
        node = children[i]
        return ret if ret = endFn node, visitNode, i if inRange
        return ret if ret = visit children[i], start, endFn, visitFn
        --i
    return

  (visitNode, start, endFn, visitFn) ->
    inRange = false
    visit visitNode, start, endFn, visitFn


$['fn']['extend']
  'contains': (arg) ->
    arg = node if node = arg['container']
    return true if arg is node = @[0]
    while arg = arg.parentNode when node is arg
      return true
    false

  # executes a function, restoring the text selection position within the container afterwards
  'keepSelection': do ->
    newStart = newEnd = start = end = startJ = endJ = j = 0

    save = (node) ->
      isStart = node is start['container']
      isEnd = node is end['container']

      if node.nodeType is TEXT_NODE
        startJ = j + start['offset'] if isStart

        if isEnd
          endJ = j + end['offset']
          return true

        j += node.nodeValue.length
      else
        i = 0; iE = (children = node.childNodes).length
        loop
          if isStart and i is start['offset']
            startJ = j

          if isEnd and i is end['offset']
            endJ = j
            return true

          break if i is iE
          return true if save children[i]
          ++i

      return

    restore = (node) ->
      isStart = node is start['container']
      isEnd = node is end['container']

      if node.nodeType is TEXT_NODE
        k = j + node.nodeValue.length

        if j <= startJ <= k and (isStart or !newStart)
          newStart ||= {}
          newStart['container'] = node
          newStart['offset'] = startJ - j

        if j <= endJ <= k and (isEnd or !newEnd)
          newEnd ||= {}
          newEnd['container'] = node
          newEnd['offset'] = endJ - j

        return true if k > endJ and k > startJ

        j = k

      else
        i = 0; iE = (children = node.childNodes).length
        loop
          if isStart and j is startJ
            newStart ||= {}
            newStart['container'] = node
            newStart['offset'] = i
            return true if !~endJ

          if isEnd and j is endJ
            newEnd ||= {}
            newEnd['container'] = node
            newEnd['offset'] = i
            return true

          break if i is iE
          return true if restore children[i]
          ++i

      return

    (selection, fn) ->
      if !fn?
        fn = selection
        selection = $['selection']()

      return fn() unless selection

      thisNode = @[0]

      start = selection['start']
      end = selection['end']
      startJ = endJ = -1
      j = 0
      save thisNode

      ret = fn()

      j = 0
      newStart = newEnd = undefined

      if ~startJ or ~endJ
        restore thisNode

        unless newStart and newEnd
          thisEnd = {'container': thisNode, 'offset': thisNode.childNodes.length}
          newStart = thisEnd if ~startJ
          newEnd = thisEnd if ~endJ

        newStart ||= $['selection']()['start']
        newEnd ||= $['selection']()['end']

        $['selection'] newStart, newEnd

      ret

  'prevTextUntil': (start, fn) ->
    text = ''
    visitTextBackwardFn @[0], start, fn, (node) ->
      str = if node is start['container'] then (''+node.nodeValue).substring(0,start['offset']) else node.nodeValue
      text = "#{str}#{text}"
      return
    text

  'nextTextUntil': (start, fn) ->
    text = ''
    visitTextForwardFn @[0], start, fn, (node) ->
      str = if node is start['container'] then (''+node.nodeValue).substring(start['offset']) else node.nodeValue
      text += str
      return
    text

  'wordEndUntil': (start, fn) ->
    thisNode = @[0]
    endFn = (node, parent, index) -> {'container': parent, 'offset': index} if fn node
    lastTextNode = undefined
    visitFn = (node) ->
      lastTextNode = node
      str = if node is start['container'] then (''+node.nodeValue).substr(start['offset']) else (''+node.nodeValue)
      {'container': node, 'offset': pos + if node is start['container'] then start['offset'] else 0} if ~(pos = str.search regexSpace)

    return ret if ret = visitTextForwardFn(thisNode, start, endFn, visitFn)

    if lastTextNode
      {'container': lastTextNode, 'offset': lastTextNode.nodeValue.length}
    else
      {'container': thisNode, 'offset': thisNode.childNodes.length}

  # or pass one selection range (not w3c range) arg
  'textInRange': (start, end) ->
    if start['start']
      end = start['end']
      start = start['start']

    if document.createRange
      range = global.document.createRange()
      range.setStart start['container'], start['offset']
      range.setEnd end['container'], end['offset']
      range.toString()

    else
      text = ''
      visitText @[0], start, end, (node) ->
        start = if node is startContainer then startOffset else 0
        end = endOffset if node is endContainer
        text += (''+node.nodeValue).substring start, end
        return
      text

  'prevText': ->
    node = @[0]
    text = ''
    text = "#{node.nodeValue}#{text}" while (node = node.previousSibling) and node.nodeType is TEXT_NODE
    text

  'prevTextNode': (newValue) ->
    node = @[0]

    if (previous = node.previousSibling) and previous.nodeType is TEXT_NODE
      node = (tnode = previous).previousSibling

      while node and node.nodeType is TEXT_NODE
        text = "#{node.nodeValue}#{text}" unless newValue?
        previous = node.previousSibling
        node.parentNode.removeChild node
        node = previous

      if newValue?
        tnode.nodeValue = newValue
      else if text
        tnode.nodeValue = "#{text}#{tnode.nodeValue}"

    else
      tnode = document.createTextNode newValue || ''
      node.parentNode.insertBefore tnode, node

    tnode

  'nextText': ->
    node = @[0]
    text = ''
    text += node.nodeValue while (node = node.nextSibling) and node.nodeType is TEXT_NODE
    text

  'nextTextNode': (newValue) ->
    node = @[0]
    text = ''

    if (next = node.nextSibling) and next.nodeType is TEXT_NODE
      node = (tnode = next).nextSibling

      while node and node.nodeType is TEXT_NODE
        text += node.nodeValue unless newValue?
        next = node.nextSibling
        node.parentNode.removeChild node
        node = next

      if newValue?
        tnode.nodeValue = newValue
      else if text
        tnode.nodeValue = "#{tnode.nodeValue}#{text}"
    else
      tnode = document.createTextNode newValue || ''
      if next
        node.parentNode.insertBefore tnode, next
      else
        node.parentNode.appendChild tnode

    tnode

if debug
  $['fn']['extend']
    'pointToString': do ->
      regex = /^(<.*?>)(<\/[^>]*>)$/
      visit = (node, point) ->
        str = ""

        if node.nodeType is TEXT_NODE
          str += "<t>"
          if point.container is node
            str += node.nodeValue.substr(0,point.offset) + "|" + node.nodeValue.substr(point.offset)
          else
            str += node.nodeValue
          str += "</t>"
        else unless m = regex.exec html = node.cloneNode(false).outerHTML.trim()
          str += html
          throw new Error "closed outerHTML but has childNodes? [#{html}]" if node.childNodes?.length
        else
          str += m[1]

          if node is point.container
            for child, i in node.childNodes
              if i is point.offset
                str += "|"
              str += visit child, point
            str += "|" if i is point.offset
          else
            str += visit child, point for child in node.childNodes

          str += m[2]

        str

      (point) ->
        return ''+point unless point?.container
        visit @[0], point

      


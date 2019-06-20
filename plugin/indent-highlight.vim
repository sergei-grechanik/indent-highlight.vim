" To make sure plugin is loaded only once,
" and to allow users to disable the plugin
" with a global conf.
if exists("g:do_not_load_indent_highlight")
  finish
endif
let g:do_not_load_indent_highlight = 1

if !exists("g:indent_highlight_bg_color")
  let g:indent_highlight_bg_color = 255
endif

function! s:InitHighlightGroup()
  " exe 'hi IndentHighlightGroup guibg=' . g:indent_highlight_bg_color . ' ctermbg=' . g:indent_highlight_bg_color
  exe 'hi IndentHighlightGroup ctermbg=' . g:indent_highlight_bg_color
endfunction

function! s:getStartDisabled()
  " Configuration to disable indent highlight when a buffer is opened.
  " This would allow users to enable it on demand.
  return get(g:, 'indent_highlight_start_disabled', 1)
endfunction

function! s:FindBlockStart(currentLine, currentIndent, limit)
  let startLineNumber = a:currentLine
  let indentLength = indent(a:currentLine)
  while s:IsLineOfSameIndent(startLineNumber, a:currentIndent)
    if a:limit >= 0 && startLineNumber < a:currentLine - a:limit
      break
    endif
    if !empty(getline(startLineNumber)) && indent(startLineNumber) < indentLength
      let indentLength = indent(startLineNumber)
    endif
    let startLineNumber -= 1
  endwhile
  return [startLineNumber, indentLength]
endfunction

function! s:FindBlockEnd(currentLine, currentIndent, limit)
  let endLineNumber = a:currentLine
  let endNonEmptyLineNumber = endLineNumber
  let indentLength = indent(a:currentLine)
  while s:IsLineOfSameIndent(endLineNumber, a:currentIndent)
    " TODO: This magic const should be a variable
    if endLineNumber > a:currentLine + a:limit
      break
    endif
    if !empty(getline(endLineNumber))
      if indent(endLineNumber) < indentLength
        let indentLength = indent(endLineNumber)
      endif
      " This is needed to prevent highlighting of trailing newlines
      let endNonEmptyLineNumber = endLineNumber + 1
    endif
    let endLineNumber += 1
  endwhile
  return [endNonEmptyLineNumber, indentLength, endLineNumber]
endfunction

function! s:JumpBlockStart()
  let currentLine = line(".")
  let currentLineIndent = indent(".")
  if virtcol(".") <= currentLineIndent
    let currentLineIndent = virtcol(".")
  end
  let blockStart = s:FindBlockStart(currentLine, currentLineIndent, 10000)
  silent execute "normal! " . blockStart[0] . "G"
endfunction

function! s:JumpBlockEnd()
  let currentLineIndent = indent(".")
  if virtcol(".") <= currentLineIndent
    let currentLineIndent = virtcol(".")
  end
  let blockStart = s:FindBlockEnd(line("."), currentLineIndent, 10000)
  silent execute "normal! " . blockStart[2] . "G"
endfunction

function! s:CurrentBlockIndentPattern(echoHeaderLine)
  let currentLineIndent = indent(".")
  " If the cursor is on the indentation space symbol, use its position to highlight indent
  if virtcol(".") <= currentLineIndent
    let currentLineIndent = virtcol(".")
  else
    " TODO: This should be a parameter, however I don't want constant highlighting
    return ""
  endif
  let currentLineNumber = line(".")
  let endNonEmptyLineNumber = currentLineNumber
  let endLineNumber = currentLineNumber
  let pattern = ""

  " TODO: This magic const should be a variable
  let blockStart = s:FindBlockStart(currentLineNumber, currentLineIndent, 200)
  let startLineNumber = blockStart[0]
  let indentLength = blockStart[1]
  " Print the header line
  if startLineNumber != currentLineNumber && a:echoHeaderLine
    echo getline(startLineNumber)
  endif
  let headerIndent = indent(startLineNumber)

  let blockEnd = s:FindBlockEnd(currentLineNumber, currentLineIndent, 100)
  let endNonEmptyLineNumber = blockEnd[0]
  if blockEnd[1] < indentLength
    let indentLength = blockEnd[1]
  end

  let b:PreviousBlockStartLine = startLineNumber
  let b:PreviousBlockEndLine = endNonEmptyLineNumber
  let b:PreviousIndent = indentLength
  if headerIndent < 0
    let headerIndent = indentLength - shiftwidth()
  endif
  if headerIndent < 0
    let headerIndent = 0
  endif
  let linePat = '\%>' . startLineNumber . 'l\%<' . endNonEmptyLineNumber . 'l'
  let colPat = '\%<' . (indentLength + 1) . 'v\%>' . headerIndent . 'v'
  return linePat . colPat
  "return '\%>' . startLineNumber . 'l\%<' . endNonEmptyLineNumber . 'l^\(' . repeat('\s', indentLength) . '\)\?'
endfunction

function! s:IsLineOfSameIndent(lineNumber, referenceIndent)
  " If currently on empty line, do not highlight anything
  if a:referenceIndent == 0
    return 0
  endif

  let lineIndent = indent(a:lineNumber)

  " lineNumber has crossed bounds.
  if lineIndent == -1
    return 0
  endif

  " Treat empty lines as current block
  if empty(getline(a:lineNumber))
    return 1
  endif

  " Treat lines with greater indent as current block
  if lineIndent >= a:referenceIndent
    return 1
  endif

  return 0
endfunction

function! RefreshIndentHighlightOnCursorMove()
  let echoHeaderLine = 0
  if exists("b:PreviousLine")
    if line('.') == b:PreviousLine
      let echoHeaderLine = 1
    endif
    " This is an exception to the whole subsequent logic: if we move inside the indentation columns,
    " perform highlighting
    if line('.') == b:PreviousLine && (virtcol('.') <= b:PreviousIndent || b:PreviousIndent < indent('.'))
      call s:DoHighlight(echoHeaderLine)
      return
    endif
    " Do nothing if cursor has not moved to a new line unless the indent has changed or
    " the cursor is on the indentation space symbol or rehighlighting is needed
    if line('.') == b:PreviousLine && indent('.') == b:PreviousIndent && virtcol('.') >= b:PreviousIndent && !b:NeedsIndentRehighlightingOnTimeout
      " TODO: need parameter: also don't do nothing, but stop highlighting
      call s:StopHighlight()
      return
    endif
    " If we are out of the previous block, stop highlighting it
    if line('.') < b:PreviousBlockStartLine || line('.') > b:PreviousBlockEndLine
      if get(w:, 'currentMatch', 0)
        call matchdelete(w:currentMatch)
        let w:currentMatch = 0
      endif
      " Rehighlight later
      let b:NeedsIndentRehighlightingOnTimeout = 1
    endif
    " If the line is empty, don't rehighlight, but change the PreviousLine
    if empty(getline('.'))
      let b:PreviousLine = line('.')
      return
    endif
    " Don't rehighlight too often
    " TODO: This magic const should be a variable
    if exists("b:PreviousIndentHighlightingTime") && reltimefloat(reltime(b:PreviousIndentHighlightingTime)) < 0.5
      " Prevent constant rehighlighting when scrolling
      " let b:PreviousIndentHighlightingTime = reltime()
      " Rehighlight later
      let b:NeedsIndentRehighlightingOnTimeout = 1
      return
    endif
  endif
  call s:DoHighlight(echoHeaderLine)
endfunction

function! RefreshIndentHighlightOnCursorHold()
  if exists("b:NeedsIndentRehighlightingOnTimeout") && b:NeedsIndentRehighlightingOnTimeout
    " If the line is empty, don't rehighlight, but change the PreviousLine
    if empty(getline('.'))
      if exists("b:PreviousLine")
        let b:PreviousLine = line('.')
      endif
      return
    endif
    call s:DoHighlight()
  endif
endfunction

function! RefreshIndentHighlightOnBufEnter()
  call s:DoHighlight()
endfunction

function! s:DoHighlight(...)
  let echoHeaderLine = get(a:, 0, 0)

  " Do nothing if indent_highlight_disabled is set globally or for buffer
  if get(g:, 'indent_highlight_disabled', 0) || get(b:, 'indent_highlight_disabled', s:getStartDisabled())
    call s:StopHighlight()
    return
  endif

  " Get the current block's pattern
  let pattern = s:CurrentBlockIndentPattern(echoHeaderLine)

  if exists("w:currentPattern") && pattern ==# w:currentPattern
    " It is the same pattern that is being highlighted
    return
  endif

  " Clear previous highlight if it exists
  call s:StopHighlight()

  if empty(pattern)
    "Do nothing if no block pattern is recognized
    return
  endif

  " Highlight the new pattern
  let w:currentMatch = matchadd("IndentHighlightGroup", pattern)
  let w:currentPattern = pattern
  let b:PreviousLine = line('.')
  " let b:PreviousIndent = indent('.')
  let b:PreviousIndentHighlightingTime = reltime()
  let b:NeedsIndentRehighlightingOnTimeout = 0
endfunction

function! s:StopHighlight()
  if get(w:, 'currentMatch', 0)
    call matchdelete(w:currentMatch)
    let w:currentMatch = 0
    let w:currentPattern = ""
    if exists("b:PreviousLine")
      let b:PreviousLine = -1
      let b:PreviousIndent = -1
    endif
  endif
endfunction

function! s:IndentHighlightHide()
  if get(w:, 'currentMatch', 0)
    call matchdelete(w:currentMatch)
    let w:currentMatch = 0
  endif
  let b:indent_highlight_disabled = 1
endfunction

function! s:IndentHighlightShow()
  let b:indent_highlight_disabled = 0
  call s:DoHighlight()
endfunction

function! s:IndentHighlightToggle()
  if get(b:, 'indent_highlight_disabled', s:getStartDisabled())
    call s:IndentHighlightShow()
  else
    call s:IndentHighlightHide()
  endif
endfunction

call s:InitHighlightGroup()

augroup indent_highlight
  autocmd!

  if !get(g:, 'indent_highlight_disabled', 0)
    " On cursor move, we check if line number has changed
    autocmd CursorMoved,CursorMovedI * call RefreshIndentHighlightOnCursorMove()
    " On timeout we check if we need to rehighlight
    autocmd CursorHold,CursorHoldI * call RefreshIndentHighlightOnCursorHold()
  endif

augroup END

" Default mapping is <Leader>ih
map <unique> <silent> <Leader>ih :IndentHighlightToggle<CR>

" If this command doesn't exist, create one.
" This is the only command available to the users.
if !exists(":IndentHighlightToggle")
  command IndentHighlightToggle  :call s:IndentHighlightToggle()
endif

if !exists(":JumpBlockStart")
  command JumpBlockStart :call s:JumpBlockStart()
endif

if !exists(":JumpBlockEnd")
  command JumpBlockEnd :call s:JumpBlockEnd()
endif

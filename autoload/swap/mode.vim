" Swapmode object - Interactive order determination.
scriptencoding utf-8

let s:Const = swap#constant#import()
let s:Lib = swap#lib#import()
let s:Clocks = swap#clock#import()

let s:TRUE = 1
let s:FALSE = 0
let s:TYPENUM = s:Const.TYPENUM
let s:TYPESTR = s:Const.TYPESTR

" phase enum
let s:FIRST = 0       " in the first target determination
let s:SECOND = 1      " in the second target determination
let s:DONE = 2        " Both the targets have been determined
let s:EXIT = 3        " cancelled by Esc

" patches
if v:version > 704 || (v:version == 704 && has('patch237'))
  let s:has_patch_7_4_311 = has('patch-7.4.311')
else
  let s:has_patch_7_4_311 = v:version == 704 && has('patch311')
endif


" sort functions
let g:swap#mode#sortfunc =
\ get(g:, 'swap#mode#sortfunc', [s:Lib.compare_ascend])
let g:swap#mode#SORTFUNC =
\ get(g:, 'swap#mode#SORTFUNC', [s:Lib.compare_descend])


" Swapmode object - for interactive determination of swap actions
let s:Swapmode = {
\   'pos': {
\     'current': 0,
\     'selected': 0,
\     'end': 0,
\   },
\   'history': [],
\   'undolevel': 0,
\ }


" This function asks user to input keys to determine an operation
function! s:Swapmode.get_input(buffer) abort "{{{
  if empty(a:buffer)
    return []
  endif

  let phase = 0
  let input = ['', '']
  let key_map = deepcopy(get(g:, 'swap#keymappings', g:swap#default_keymappings))
  let self.pos.current = 0
  let self.pos.selected = 0
  let self.pos.end = len(a:buffer.items)

  let pos = self.get_nonblank_pos('#', a:buffer)
  call self.showmode()
  call self.set_current(pos, a:buffer)
  call self.update_highlight(a:buffer) | redraw
  try
    while phase < s:DONE
      let key = s:prompt(key_map)
      let [phase, input] = self.execute(key, phase, input, a:buffer)
    endwhile
  catch /^Vim:Interrupt$/
    let phase = s:EXIT
  finally
    call self.clear_highlight(a:buffer)
    " clear messages
    echo ''
  endtry

  if phase is# s:EXIT
    return []
  endif

  if input[0] isnot# 'undo'
    call self.add_history(input, a:buffer)
  endif
  return input
endfunction "}}}


function! s:Swapmode.showmode() abort "{{{
  if !&showmode
    return
  endif
  echohl ModeMsg
  echo '-- Swap mode --'
  echohl NONE
endfunction "}}}


function! s:Swapmode.revise_cursor_pos(buffer) abort  "{{{
  let curpos = getpos('.')
  let item = a:buffer.get_item(self.pos.current)
  if !empty(item) &&
  \  s:Lib.is_in_between(curpos, item.head, item.tail) &&
  \  curpos != item.tail
    " no problem!
    return
  endif

  let head = a:buffer.head
  let tail = a:buffer.tail
  if s:Lib.in_order_of(curpos, head)
    let self.pos.current = 0
  elseif curpos == tail || s:Lib.in_order_of(tail, curpos)
    let self.pos.current = self.pos.end + 1
  else
    let self.pos.current = a:buffer.update_sharp(curpos)
  endif
  call self.update_highlight(a:buffer)
endfunction "}}}


function! s:Swapmode.execute(funclist, phase, input, buffer) abort "{{{
  let phase = a:phase
  let input = a:input
  for name in a:funclist
    let fname = 'key_' . name
    let [phase, input] = self[fname](phase, input, a:buffer)
    if phase is# s:DONE
      break
    endif
  endfor
  call self.revise_cursor_pos(a:buffer)
  redraw
  return [phase, input]
endfunction "}}}


" A history item is a dictionary which has the following keys:
"   input : the determined input
"   buffer: the buffer before changed by the input
"   cursor: the positional number of cursor when the buffer is restored
function! s:Swapmode.add_history(input, buffer) abort  "{{{
  call self._truncate_history()
  let histitem = {
  \   'input': copy(a:input),
  \   'buffer': deepcopy(a:buffer),
  \   'cursor': self.pos.current,
  \ }
  call add(self.history, histitem)
endfunction "}}}


function! s:Swapmode._truncate_history() abort  "{{{
  if self.undolevel == 0
    return self.history
  endif
  let endidx = -1*self.undolevel
  call remove(self.history, endidx, -1)
  let self.undolevel = 0
  return self.history
endfunction "}}}


function! s:Swapmode.export_history() abort "{{{
  return map(copy(self.history), 'v:val.input')
endfunction "}}}


function! s:Swapmode.set_current(pos, buffer) abort "{{{
  let item = a:buffer.get_item(a:pos)
  if empty(item)
    return
  endif
  call item.cursor()

  " update side-scrolling
  " FIXME: Any standard way?
  if s:has_patch_7_4_311
    call winrestview({})
  endif

  let self.pos.current = a:pos
endfunction "}}}


function! s:Swapmode.get_nonblank_pos(pos, buffer) abort "{{{
  let item = a:buffer.get_item(a:pos, a:buffer)
  if empty(item)
    return self.pos.end
  endif
  if item.str isnot# ''
    return a:buffer.get_pos(a:pos)
  endif
  return s:next_nonblank(a:buffer.items, a:buffer.get_pos(a:pos))
endfunction "}}}


function! s:Swapmode.clear_highlight(buffer) abort  "{{{
  " NOTE: This function itself does not redraw.
  if !g:swap#highlight
    return
  endif

  for item in a:buffer.items
    call item.clear_highlight()
  endfor
endfunction "}}}


function! s:Swapmode.update_highlight(buffer) abort  "{{{
  if !g:swap#highlight
    return
  endif

  for [i, item] in s:Lib.enumerate(a:buffer.items)
    let pos = i + 1
    let higroup = s:higroup(pos, self.pos)
    if item.higroup isnot# higroup
      call item.clear_highlight()
      call item.highlight(higroup)
    endif
  endfor
endfunction "}}}


function! s:higroup(p, pos) abort "{{{
  if a:p == a:pos.current
    return 'SwapCurrentItem'
  elseif a:p == a:pos.selected
    return 'SwapSelectedItem'
  endif
  return 'SwapItem'
endfunction "}}}


let s:NOTHING = 0

function! s:Swapmode.select(pos) abort "{{{
  let self.pos.selected = str2nr(a:pos)
endfunction "}}}


function! s:Swapmode.pos.is_valid(pos) abort  "{{{
  let pos = str2nr(a:pos)
  return pos >= 1 && pos <= self.end
endfunction "}}}


function! s:prompt(key_map) abort "{{{
  let key_map = insert(copy(a:key_map), {'input': "\<Esc>", 'output': ['Esc']})   " for safety
  let clock = s:Clocks.Clock()
  let timeoutlen = g:swap#timeoutlen

  let input = ''
  let last_compl_match = ['', []]
  while key_map != []
    let c = getchar(0)
    if empty(c)
      if clock.started && timeoutlen > 0 && clock.elapsed() > timeoutlen
        let [input, key_map] = last_compl_match
        break
      else
        sleep 20m
        continue
      endif
    endif

    let c = type(c) == s:TYPENUM ? nr2char(c) : c
    let input .= c

    " check forward match
    let n_fwd = len(filter(key_map, 's:is_input_matched(v:val, input, 0)'))

    " check complete match
    let n_comp = len(filter(copy(key_map), 's:is_input_matched(v:val, input, 1)'))
    if n_comp
      if len(key_map) == n_comp
        break
      else
        call clock.stop()
        call clock.start()
        let last_compl_match = [input, copy(key_map)]
      endif
    else
      if clock.started && !n_fwd
        let [input, key_map] = last_compl_match
        break
      endif
    endif
  endwhile
  call clock.stop()

  if filter(key_map, 's:is_input_matched(v:val, input, 1)') != []
    let key = key_map[-1]
  else
    let key = {}
  endif
  return get(key, 'output', [])
endfunction "}}}


function! s:is_input_matched(candidate, input, flag) abort "{{{
  if !has_key(a:candidate, 'output') || !has_key(a:candidate, 'input')
    return 0
  endif

  if !a:flag && a:input is# ''
    return 1
  endif

  " If a:flag == 0, check forward match. Otherwise, check complete match.
  if a:flag
    return a:input is# a:candidate.input
  endif

  let idx = strlen(a:input) - 1
  return a:input is# a:candidate.input[: idx]
endfunction "}}}


function! s:prev_nonblank(items, currentpos) abort  "{{{
  " skip empty items
  let idx = a:currentpos - 2
  while idx >= 0
    if a:items[idx].str isnot# ''
      return idx + 1
    endif
    let idx -= 1
  endwhile
  return a:currentpos
endfunction "}}}


function! s:next_nonblank(items, currentpos) abort  "{{{
  " skip empty items
  let idx = a:currentpos
  let end = len(a:items) - 1
  while idx <= end
    if a:items[idx].str isnot# ''
      return idx + 1
    endif
    let idx += 1
  endwhile
  return a:currentpos
endfunction "}}}


" NOTE: Key function list
"    {0~9} : Input {0~9} to specify an item.
"    CR    : Fix the input number. If nothing has been input, fix to the item under the cursor.
"    BS    : Erase the previous input.
"    undo  : Undo the current operation.
"    redo  : Redo the previous operation.
"    current : Fix to the item under the cursor.
"    move_prev : Move to the previous item.
"    move_next : Move to the next item.
"    swap_prev : Swap the current item with the previous item.
"    swap_next : Swap the current item with the next item.
function! s:Swapmode.key_nr(nr, phase, input, buffer) abort  "{{{
  if a:phase >= s:DONE
    return [a:phase, a:input]
  endif

  let input = s:append(a:input, a:phase, a:nr)
  return [a:phase, input]
endfunction "}}}
function! s:Swapmode.key_0(phase, input, buffer) abort "{{{
  return self.key_nr(0, a:phase, a:input, a:buffer)
endfunction "}}}
function! s:Swapmode.key_1(phase, input, buffer) abort "{{{
  return self.key_nr(1, a:phase, a:input, a:buffer)
endfunction "}}}
function! s:Swapmode.key_2(phase, input, buffer) abort "{{{
  return self.key_nr(2, a:phase, a:input, a:buffer)
endfunction "}}}
function! s:Swapmode.key_3(phase, input, buffer) abort "{{{
  return self.key_nr(3, a:phase, a:input, a:buffer)
endfunction "}}}
function! s:Swapmode.key_4(phase, input, buffer) abort "{{{
  return self.key_nr(4, a:phase, a:input, a:buffer)
endfunction "}}}
function! s:Swapmode.key_5(phase, input, buffer) abort "{{{
  return self.key_nr(5, a:phase, a:input, a:buffer)
endfunction "}}}
function! s:Swapmode.key_6(phase, input, buffer) abort "{{{
  return self.key_nr(6, a:phase, a:input, a:buffer)
endfunction "}}}
function! s:Swapmode.key_7(phase, input, buffer) abort "{{{
  return self.key_nr(7, a:phase, a:input, a:buffer)
endfunction "}}}
function! s:Swapmode.key_8(phase, input, buffer) abort "{{{
  return self.key_nr(8, a:phase, a:input, a:buffer)
endfunction "}}}
function! s:Swapmode.key_9(phase, input, buffer) abort "{{{
  return self.key_nr(9, a:phase, a:input, a:buffer)
endfunction "}}}


function! s:Swapmode.key_CR(phase, input, buffer) abort  "{{{
  if a:phase >= s:DONE
    return [a:phase, a:input]
  endif

  let input = a:input[a:phase]
  if input is# ''
    return self.key_current(a:phase, a:input, a:buffer)
  endif
  return self.key_fix_nr(a:phase, a:input, a:buffer)
endfunction "}}}


function! s:Swapmode.key_BS(phase, input, buffer) abort  "{{{
  let phase = a:phase
  let input = a:input
  if phase is# s:FIRST
    if a:input[s:FIRST] isnot# ''
      let input = s:truncate(a:input, s:FIRST)
    endif
  elseif phase is# s:SECOND
    if a:input[s:SECOND] isnot# ''
      let input = s:truncate(a:input, s:SECOND)
    else
      let input = s:truncate(a:input, s:FIRST)
      let phase = s:FIRST
      call self.select(s:NOTHING)
      call self.update_highlight(a:buffer)
    endif
  endif
  return [phase, input]
endfunction "}}}


function! s:Swapmode.key_undo(phase, input, buffer) abort "{{{
  if a:phase >= s:DONE
    return [a:phase, a:input]
  endif

  if len(self.history) <= self.undolevel
    return [a:phase, a:input]
  endif

  let phase = s:DONE
  let prev = self.history[-1*(self.undolevel+1)]
  " The last input item is the cursor position after undoing
  let input = ['undo', prev.buffer, prev.cursor]
  let self.undolevel += 1
  return [phase, input]
endfunction "}}}


function! s:Swapmode.key_redo(phase, input, buffer) abort "{{{
  if a:phase >= s:DONE
    return [a:phase, a:input]
  endif

  if self.undolevel == 0
    return [a:phase, a:input]
  endif

  let phase = s:DONE
  let next = self.history[-1*self.undolevel]
  let input = next.input
  let self.undolevel -= 1
  return [phase, input]
endfunction "}}}


function! s:Swapmode.key_current(phase, input, buffer) abort "{{{
  let phase = a:phase
  let input = s:set(a:input, phase, string(self.pos.current))
  if phase is# s:FIRST
    let phase = s:SECOND
    call self.select(input[0])
    call self.update_highlight(a:buffer)
  elseif phase is# s:SECOND
    let phase = s:DONE
  endif
  return [phase, input]
endfunction "}}}


function! s:Swapmode.key_fix_nr(phase, input, buffer) abort "{{{
  let phase = a:phase
  if phase is# s:FIRST
    let pos = str2nr(a:input[s:FIRST])
    if self.pos.is_valid(pos)
      call self.set_current(pos, a:buffer)
      let phase = s:SECOND
      call self.select(a:input[0])
      call self.update_highlight(a:buffer)
    endif
  elseif phase is# s:SECOND
    let pos = str2nr(a:input[s:SECOND])
    if self.pos.is_valid(pos)
      let phase = s:DONE
    endif
  endif
  return [phase, a:input]
endfunction "}}}


function! s:Swapmode.key_move_prev(phase, input, buffer) abort  "{{{
  if a:phase >= s:DONE
    return [a:phase, a:input]
  endif
  if self.pos.current <= 0
    return [a:phase, a:input]
  endif

  let pos = s:prev_nonblank(a:buffer.items,
  \                         min([self.pos.current, self.pos.end+1]))
  call self.set_current(pos, a:buffer)
  call self.update_highlight(a:buffer)
  return [a:phase, a:input]
endfunction "}}}


function! s:Swapmode.key_move_next(phase, input, buffer) abort  "{{{
  if a:phase >= s:DONE
    return [a:phase, a:input]
  endif
  if self.pos.current >= self.pos.end
    return [a:phase, a:input]
  endif

  let pos = s:next_nonblank(a:buffer.items,
  \                         max([0, self.pos.current]))
  call self.set_current(pos, a:buffer)
  call self.update_highlight(a:buffer)
  return [a:phase, a:input]
endfunction "}}}


function! s:Swapmode.key_swap_prev(phase, input, buffer) abort  "{{{
  if a:phase >= s:DONE
    return [a:phase, a:input]
  endif
  if self.pos.current < 2 || self.pos.current > self.pos.end
    return [a:phase, a:input]
  endif

  let input = [self.pos.current, self.pos.current - 1]
  let phase = s:DONE
  return [phase, input]
endfunction "}}}


function! s:Swapmode.key_swap_next(phase, input, buffer) abort  "{{{
  if a:phase >= s:DONE
    return [a:phase, a:input]
  endif
  if self.pos.current < 1 || self.pos.current > self.pos.end - 1
    return [a:phase, a:input]
  endif

  let input = [self.pos.current, self.pos.current + 1]
  let phase = s:DONE
  return [phase, input]
endfunction "}}}


function! s:Swapmode.key_sort(phase, input, buffer) abort "{{{
  if a:phase >= s:DONE
    return [a:phase, a:input]
  endif

  let input = ['sort', 1, '$'] + g:swap#mode#sortfunc
  let phase = s:DONE
  return [phase, input]
endfunction "}}}


function! s:Swapmode.key_SORT(phase, input, buffer) abort "{{{
  if a:phase >= s:DONE
    return [a:phase, a:input]
  endif

  let input = ['sort', 1, '$'] + g:swap#mode#SORTFUNC
  let phase = s:DONE
  return [phase, input]
endfunction "}}}


function! s:Swapmode.key_group(phase, input, buffer) abort  "{{{
  if a:phase >= s:DONE
    return [a:phase, a:input]
  endif
  if len(a:buffer.items) < 2
    return [a:phase, a:input]
  endif
  if self.pos.current < 1 || self.pos.current > self.pos.end - 1
    return [a:phase, a:input]
  endif

  let input = ['group', self.pos.current, self.pos.current + 1]
  return [s:DONE, input]
endfunction "}}}


function! s:Swapmode.key_ungroup(phase, input, buffer) abort  "{{{
  if a:phase >= s:DONE
    return [a:phase, a:input]
  endif
  if self.pos.current < 1 || self.pos.current > self.pos.end
    return [a:phase, a:input]
  endif

  let input = ['ungroup', self.pos.current]
  return [s:DONE, input]
endfunction "}}}


function! s:Swapmode.key_breakup(phase, input, buffer) abort "{{{
  if a:phase >= s:DONE
    return [a:phase, a:input]
  endif
  if self.pos.current < 1 || self.pos.current > self.pos.end
    return [a:phase, a:input]
  endif

  let input = ['breakup', self.pos.current]
  return [s:DONE, input]
endfunction "}}}


function! s:Swapmode.key_reverse(phase, input, buffer) abort "{{{
  if a:phase >= s:DONE
    return [a:phase, a:input]
  endif

  let input = ['reverse']
  let phase = s:DONE
  return [phase, input]
endfunction "}}}


function! s:Swapmode.key_Esc(phase, input, buffer) abort  "{{{
  let phase = s:EXIT
  return [phase, a:input]
endfunction "}}}


function! s:set(input, phase, v) abort "{{{
  if a:phase is# s:FIRST
    let a:input[0] = a:v
  elseif a:phase is# s:SECOND
    let a:input[1] = a:v
  else
    echoerr 'vim-swap: Invalid argument for s:set() in autoload/swap/swapmode.vim'
  endif
  return a:input
endfunction "}}}


function! s:append(input, phase, v) abort "{{{
  if a:phase is# s:FIRST
    let a:input[0] .= a:v
  elseif a:phase is# s:SECOND
    let a:input[1] .= a:v
  else
    echoerr 'vim-swap: Invalid argument for s:append() in autoload/swap/swapmode.vim'
  endif
  return a:input
endfunction "}}}


function! s:truncate(input, phase) abort "{{{
  if a:phase is# s:FIRST
    let a:input[0] = a:input[0][0:-2]
  elseif a:phase is# s:SECOND
    let a:input[1] = a:input[1][0:-2]
  else
    echoerr 'vim-swap: Invalid argument for s:truncate() in autoload/swap/swapmode.vim'
  endif
  return a:input
endfunction "}}}


let s:Mode = {}


function! s:Mode.Swapmode() abort "{{{
  return deepcopy(s:Swapmode)
endfunction "}}}


function! swap#mode#import() abort  "{{{
  return s:Mode
endfunction "}}}


" vim:set foldmethod=marker:
" vim:set commentstring="%s:
" vim:set ts=2 sts=2 sw=2:

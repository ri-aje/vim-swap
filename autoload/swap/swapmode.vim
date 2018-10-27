" swapmode object - Interactive order determination.

let s:const = swap#constant#import()
let s:lib = swap#lib#import()

let s:TRUE = 1
let s:FALSE = 0
let s:TYPENUM = s:const.TYPENUM
let s:TYPESTR = s:const.TYPESTR

" phase enum
let s:FIRST = 0       " in the first target determination
let s:SECOND = 1      " in the second target determination
let s:DONE = 2        " Both the targets have been determined
let s:CANCELLED = 3   " cancelled by Esc

" patches
if v:version > 704 || (v:version == 704 && has('patch237'))
  let s:has_patch_7_4_311 = has('patch-7.4.311')
else
  let s:has_patch_7_4_311 = v:version == 704 && has('patch311')
endif


function! swap#swapmode#new() abort  "{{{
  return deepcopy(s:swapmode_prototype)
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


" swapmode object - for interactive determination of swap actions
" swap#swapmode#new() returns a instance of this object
let s:swapmode_prototype = {
      \   'pos': {
      \     'current': 0,
      \     'end': 0,
      \     'last_current': 0,
      \     'selected': 0,
      \   },
      \   'buffer': {},
      \   'history': [],
      \   'undolevel': 0,
      \ }


" This function asks user to input keys to determine an operation
function! s:swapmode_prototype.get_input(buffer) dict abort "{{{
  if empty(a:buffer)
    return []
  endif

  let phase = 0
  let input = ['', '']
  let key_map = deepcopy(get(g:, 'swap#keymappings', g:swap#default_keymappings))
  let self.buffer = a:buffer
  let self.pos.current = 0
  let self.pos.last_current = 0
  let self.pos.selected = 0
  let self.pos.end = len(self.buffer.items)

  let pos = self.get_nonblank_pos('#')
  call self.set_current(pos)
  call self.echo(phase, input)
  call self.highlight()
  redraw
  try
    while phase < s:DONE
      let key = s:prompt(key_map)
      let [phase, input] = self.execute(key, phase, input)
    endwhile
  catch /^Vim:Interrupt$/
  finally
    call self.clear_highlight()
    " clear messages
    echo ''
  endtry

  if phase is# s:CANCELLED
    return []
  endif

  if input[0] isnot# 'undo'
    call self.add_history(input)
  endif
  return input
endfunction "}}}


function! s:swapmode_prototype.echo(phase, input) dict abort "{{{
  if a:phase >= s:DONE
    return
  endif

  let max_len = &columns - 25
  let message = []

  for histitem in self.history[: -1*(self.undolevel+1)]
    let message += [[histitem.input[0], g:swap#hl_itemnr]]
    let message += [[g:swap#arrow, g:swap#hl_arrow]]
    let message += [[histitem.input[1], g:swap#hl_itemnr]]
    let message += [[', ', 'NONE']]
  endfor
  if a:phase is# s:FIRST
    if a:input[0] isnot# ''
      let higoup = self.pos.is_valid(a:input[0])
               \ ? g:swap#hl_itemnr : 'ErrorMsg'
      let message += [[a:input[0], higoup]]
    else
      if !empty(message)
        call remove(message, -1)
      endif
    endif
  elseif a:phase == 1
    if a:input[1] isnot# ''
      let message += [[a:input[0], g:swap#hl_itemnr]]
      let message += [[g:swap#arrow, g:swap#hl_arrow]]
      let higoup = self.pos.is_valid(a:input[1])
               \ ? g:swap#hl_itemnr : 'ErrorMsg'
      let message += [[a:input[1], higoup]]
    else
      let message += [[a:input[0], g:swap#hl_itemnr]]
      let message += [[g:swap#arrow, g:swap#hl_arrow]]
    endif
  endif

  if message != []
    let len = eval(join(map(copy(message), 'strwidth(v:val[0])'), '+'))
    if len > max_len
      while len > max_len-1
        let mes  = remove(message, 0)
        let len -= strwidth(mes[0])
      endwhile
      if len < 0
        let mes = [mes[0][len :], mes[1]]
        call insert(message, mes)
      endif
      let precedes = matchstr(&listchars, 'precedes:\zs.\ze')
      let precedes = precedes is# '' ? '<' : precedes
      call insert(message, [precedes, 'SpecialKey'])
    endif
  endif

  echohl ModeMsg
  echo 'Swap mode: '
  for mes in message
    execute 'echohl ' . mes[1]
    echon mes[0]
  endfor
  echohl NONE
endfunction "}}}


function! s:swapmode_prototype.revise_cursor_pos() dict abort  "{{{
  let curpos = getpos('.')
  let item = self.get_current_item()
  if !empty(item) &&
      \ s:lib.is_in_between(curpos, item.region.head, item.region.tail) &&
      \ curpos != item.region.tail
    " no problem!
    return
  endif

  let head = self.get_first_item().region.head
  let tail = self.get_last_item().region.tail
  let self.pos.last_current = self.pos.current
  if s:lib.is_ahead(head, curpos)
    let self.pos.current = 0
  elseif curpos == tail || s:lib.is_ahead(curpos, tail)
    let self.pos.current = self.pos.end + 1
  else
    let self.pos.current = self.buffer.update_sharp(curpos)
  endif
  call self.update_highlight()
endfunction "}}}


function! s:swapmode_prototype.execute(funclist, phase, input) abort "{{{
  let phase = a:phase
  let input = a:input
  for name in a:funclist
    let fname = 'key_' . name
    let [phase, input] = self[fname](a:phase, input)
    if phase is# s:DONE
      break
    endif
  endfor
  call self.revise_cursor_pos()
  redraw
  return [phase, input]
endfunction "}}}


" A history item is a dictionary which has the following keys:
"   input : the determined input
"   buffer: the buffer before changed by the input
"   cursor: the positional number of cursor when the buffer is restored
function! s:swapmode_prototype.add_history(input) dict abort  "{{{
  call self._truncate_history()
  let histitem = {
    \ 'input': copy(a:input),
    \ 'buffer': deepcopy(self.buffer),
    \ 'cursor': self.pos.current,
    \ }
  call add(self.history, histitem)
endfunction "}}}


function! s:swapmode_prototype._truncate_history() dict abort  "{{{
  if self.undolevel == 0
    return self.history
  endif
  let endidx = -1*self.undolevel
  call remove(self.history, endidx, -1)
  let self.undolevel = 0
  return self.history
endfunction "}}}


function! s:swapmode_prototype.export_history() abort "{{{
  return map(copy(self.history), 'v:val.input')
endfunction "}}}


function! s:swapmode_prototype.set_current(pos) dict abort "{{{
  let item = self.get_item(a:pos)
  if empty(item)
    return
  endif
  call item.cursor()

  " update side-scrolling
  " FIXME: Any standard way?
  if s:has_patch_7_4_311
    call winrestview({})
  endif

  let self.pos.last_current = self.pos.current
  let self.pos.current = a:pos
endfunction "}}}


function! s:swapmode_prototype.get_pos(pos) abort "{{{
  if type(a:pos) is# s:TYPENUM && self.pos.is_valid(a:pos)
    return a:pos
  elseif type(a:pos) is# s:TYPESTR && has_key(self.buffer.mark, a:pos)
    return self.get_pos(self.buffer.mark[a:pos])
  endif
  return 0
endfunction "}}}


function! s:swapmode_prototype.get_item(pos) abort "{{{
  let pos = self.get_pos(a:pos)
  if pos == 0
    return {}
  endif
  return self.buffer.items[a:pos - 1]
endfunction "}}}


function! s:swapmode_prototype.get_current_item() abort "{{{
  return self.get_item(self.pos.current)
endfunction "}}}


function! s:swapmode_prototype.get_first_item() abort "{{{
  return self.get_item(1)
endfunction "}}}


function! s:swapmode_prototype.get_last_item() abort "{{{
  return self.get_item(self.pos.end)
endfunction "}}}


function! s:swapmode_prototype.get_nonblank_pos(pos) abort "{{{
  let item = self.get_item(a:pos)
  if empty(item)
    return self.pos.end
  endif
  if item.string isnot# ''
    return self.get_pos(a:pos)
  endif
  return s:next_nonblank(self.buffer.items, self.get_pos(a:pos))
endfunction "}}}


function! s:swapmode_prototype.highlight() dict abort "{{{
  if !g:swap#highlight
    return
  endif

  let pos = 1
  for item in self.buffer.items
    if pos == self.pos.current
      call item.highlight('SwapCurrentItem')
    else
      call item.highlight('SwapItem')
    endif
    let pos += 1
  endfor
endfunction "}}}


function! s:swapmode_prototype.clear_highlight() dict abort  "{{{
  " NOTE: This function itself does not redraw.
  if !g:swap#highlight
    return
  endif

  for item in self.buffer.items
    if item.highlightid != []
      call item.clear_highlight()
    endif
  endfor
endfunction "}}}


function! s:swapmode_prototype.update_highlight() dict abort  "{{{
  if !g:swap#highlight
    return
  endif

  let last_current = self.get_item(self.pos.last_current)
  if !empty(last_current)
    call last_current.clear_highlight()
    call last_current.highlight('SwapItem')
  endif

  let selected = self.get_item(self.pos.selected)
  if !empty(selected)
    call selected.clear_highlight()
    call selected.highlight('SwapSelectedItem')
  endif

  let current = self.get_item(self.pos.current)
  if !empty(current)
    call current.clear_highlight()
    call current.highlight('SwapCurrentItem')
  endif
endfunction "}}}


let s:NOTHING = 0

function! s:swapmode_prototype.select(pos) abort "{{{
  let self.pos.selected = str2nr(a:pos)
endfunction "}}}


function! s:swapmode_prototype.pos.is_valid(pos) dict abort  "{{{
  let pos = str2nr(a:pos)
  return pos >= 1 && pos <= self.end
endfunction "}}}


function! s:prompt(key_map) abort "{{{
  let key_map = insert(copy(a:key_map), {'input': "\<Esc>", 'output': ['Esc']})   " for safety
  let clock = swap#clock#new()
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
    if a:items[idx].string isnot# ''
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
    if a:items[idx].string isnot# ''
      return idx + 1
    endif
    let idx += 1
  endwhile
  return a:currentpos
endfunction "}}}


function! s:flip(input) abort "{{{
  return [a:input[1], a:input[0]]
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
function! s:swapmode_prototype.key_nr(nr, phase, input) dict abort  "{{{
  if a:phase >= s:DONE
    return [a:phase, a:input]
  endif

  let input = s:append(a:input, a:phase, a:nr)
  call self.echo(a:phase, input)
  return [a:phase, input]
endfunction "}}}
function! s:swapmode_prototype.key_0(phase, input) abort "{{{
  return self.key_nr(0, a:phase, a:input)
endfunction "}}}
function! s:swapmode_prototype.key_1(phase, input) abort "{{{
  return self.key_nr(1, a:phase, a:input)
endfunction "}}}
function! s:swapmode_prototype.key_2(phase, input) abort "{{{
  return self.key_nr(2, a:phase, a:input)
endfunction "}}}
function! s:swapmode_prototype.key_3(phase, input) abort "{{{
  return self.key_nr(3, a:phase, a:input)
endfunction "}}}
function! s:swapmode_prototype.key_4(phase, input) abort "{{{
  return self.key_nr(4, a:phase, a:input)
endfunction "}}}
function! s:swapmode_prototype.key_5(phase, input) abort "{{{
  return self.key_nr(5, a:phase, a:input)
endfunction "}}}
function! s:swapmode_prototype.key_6(phase, input) abort "{{{
  return self.key_nr(6, a:phase, a:input)
endfunction "}}}
function! s:swapmode_prototype.key_7(phase, input) abort "{{{
  return self.key_nr(7, a:phase, a:input)
endfunction "}}}
function! s:swapmode_prototype.key_8(phase, input) abort "{{{
  return self.key_nr(8, a:phase, a:input)
endfunction "}}}
function! s:swapmode_prototype.key_9(phase, input) abort "{{{
  return self.key_nr(9, a:phase, a:input)
endfunction "}}}


function! s:swapmode_prototype.key_CR(phase, input) dict abort  "{{{
  if a:phase >= s:DONE
    return [a:phase, a:input]
  endif

  let input = a:input[a:phase]
  if input is# ''
    return self.key_current(a:phase, a:input)
  endif
  return self.key_fix_nr(a:phase, a:input)
endfunction "}}}


function! s:swapmode_prototype.key_BS(phase, input) dict abort  "{{{
  let phase = a:phase
  let input = a:input
  if phase is# s:FIRST
    if a:input[s:FIRST] isnot# ''
      let input = s:truncate(a:input, s:FIRST)
      call self.echo(phase, input)
    endif
  elseif phase is# s:SECOND
    if a:input[s:SECOND] isnot# ''
      let input = s:truncate(a:input, s:SECOND)
    else
      let input = s:truncate(a:input, s:FIRST)
      let phase = s:FIRST
      call self.select(s:NOTHING)
      call self.update_highlight()
    endif
    call self.echo(phase, input)
  endif
  return [phase, input]
endfunction "}}}


function! s:swapmode_prototype.key_undo(phase, input) dict abort "{{{
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


function! s:swapmode_prototype.key_redo(phase, input) dict abort "{{{
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


function! s:swapmode_prototype.key_current(phase, input) dict abort "{{{
  let phase = a:phase
  let input = s:set(a:input, phase, string(self.pos.current))
  if phase is# s:FIRST
    let phase = s:SECOND
    call self.select(input[0])
    call self.echo(phase, input)
  elseif phase is# s:SECOND
    let phase = s:DONE
  endif
  return [phase, input]
endfunction "}}}


function! s:swapmode_prototype.key_fix_nr(phase, input) dict abort "{{{
  let phase = a:phase
  if phase is# s:FIRST
    let pos = str2nr(a:input[s:FIRST])
    if self.pos.is_valid(pos)
      call self.set_current(pos)
      let phase = s:SECOND
      call self.select(a:input[0])
      call self.echo(phase, a:input)
      call self.update_highlight()
    endif
  elseif phase is# s:SECOND
    let pos = str2nr(a:input[s:SECOND])
    if self.pos.is_valid(pos)
      let phase = s:DONE
    else
      call self.echo(phase, a:input)
    endif
  endif
  return [phase, a:input]
endfunction "}}}


function! s:swapmode_prototype.key_move_prev(phase, input) dict abort  "{{{
  if a:phase >= s:DONE
    return [a:phase, a:input]
  endif
  if self.pos.current <= 0
    return [a:phase, a:input]
  endif

  let pos = s:prev_nonblank(self.buffer.items,
            \ min([self.pos.current, self.pos.end+1]))
  call self.set_current(pos)
  call self.update_highlight()
  return [a:phase, a:input]
endfunction "}}}


function! s:swapmode_prototype.key_move_next(phase, input) dict abort  "{{{
  if a:phase >= s:DONE
    return [a:phase, a:input]
  endif
  if self.pos.current >= self.pos.end
    return [a:phase, a:input]
  endif

  let pos = s:next_nonblank(self.buffer.items,
            \ max([0, self.pos.current]))
  call self.set_current(pos)
  call self.update_highlight()
  return [a:phase, a:input]
endfunction "}}}


function! s:swapmode_prototype.key_swap_prev(phase, input) dict abort  "{{{
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


function! s:swapmode_prototype.key_swap_next(phase, input) dict abort  "{{{
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


function! s:swapmode_prototype.key_Esc(phase, input) dict abort  "{{{
  call self.echo(a:phase, a:input)
  let phase = s:CANCELLED
  return [phase, a:input]
endfunction "}}}


" vim:set foldmethod=marker:
" vim:set commentstring="%s:
" vim:set ts=2 sts=2 sw=2:

" MIT License. Copyright (c) 2013-2017 C.Brabandt
" vim: et ts=2 sts=2 sw=2

let s:untracked_jobs = {}
let s:mq_jobs        = {}
let s:po_jobs        = {}

" Generic functions handling on exit event of the various async functions
function! s:untracked_output(dict, buf)
  if a:buf =~? ('^'. a:dict.cfg['untracked_mark'])
    let a:dict.cfg.untracked[a:dict.file] = get(g:, 'airline#extensions#branch#notexists', g:airline_symbols.notexists)
  else
    let a:dict.cfg.untracked[a:dict.file] = ''
  endif
endfunction

function! s:mq_output(buf, file)
  let buf=''
  if !empty(a:buf)
    if a:buf is# 'no patches applied' ||
      \ a:buf =~# "unknown command 'qtop'"
      let buf = ''
    elseif exists("b:mq") && b:mq isnot# a:buf
      " make sure, statusline is updated
      unlet! b:airline_head
    endif
    let b:mq = a:buf
  endif
  if has_key(s:mq_jobs, a:file)
    call remove(s:mq_jobs, a:file)
  endif
endfunction

function! s:po_output(buf, file)
  if !empty(a:buf)
    let b:airline_po_stats = printf("[%s]", a:buf)
  else
    let b:airline_po_stats = ''
  endif
  if has_key(s:po_jobs, a:file)
    call remove(s:po_jobs, a:file)
  endif
endfunction

if v:version >= 800 && has("job")
  " Vim 8.0 with Job feature

  function! s:on_stdout(channel, msg) dict abort
    let self.buf .= a:msg
  endfunction

  function! s:on_exit_mq(channel) dict abort
    call s:mq_output(self.buf, self.file)
  endfunction

  function! s:on_exit_untracked(channel) dict abort
    call s:untracked_output(self, self.buf)
    if has_key(s:untracked_jobs, self.file)
      call remove(s:untracked_jobs, self.file)
    endif
  endfunction

  function! s:on_exit_po(channel) dict abort
    call s:po_output(self.buf, self.file)
    call airline#extensions#po#shorten()
  endfunction

  function! airline#async#get_mq_async(cmd, file)
    if g:airline#init#is_windows && &shell =~ 'cmd'
      let cmd = a:cmd
    else
      let cmd = ['sh', '-c', a:cmd]
    endif

    let options = {'cmd': a:cmd, 'buf': '', 'file': a:file}
    if has_key(s:mq_jobs, a:file)
      if job_status(get(s:mq_jobs, a:file)) == 'run'
        return
      elseif has_key(s:mq_jobs, a:file)
        call remove(s:mq_jobs, a:file)
      endif
    endif
    let id = job_start(cmd, {
          \ 'err_io':   'out',
          \ 'out_cb':   function('s:on_stdout', options),
          \ 'close_cb': function('s:on_exit_mq', options)})
    let s:mq_jobs[a:file] = id
  endfunction

  function! airline#async#get_msgfmt_stat(cmd, file)
    if g:airline#init#is_windows || !executable('msgfmt')
      " no msgfmt on windows?
      return
    else
      let cmd = ['sh', '-c', a:cmd. shellescape(a:file)]
    endif

    let options = {'buf': '', 'file': a:file}
    if has_key(s:po_jobs, a:file)
      if job_status(get(s:po_jobs, a:file)) == 'run'
        return
      elseif has_key(s:po_jobs, a:file)
        call remove(s:po_jobs, a:file)
      endif
    endif
    let id = job_start(cmd, {
          \ 'err_io':   'out',
          \ 'out_cb':   function('s:on_stdout', options),
          \ 'close_cb': function('s:on_exit_po', options)})
    let s:po_jobs[a:file] = id
  endfunction

  function airline#async#vim_vcs_untracked(config, file)
    if g:airline#init#is_windows && &shell =~ 'cmd'
      let cmd = a:config['cmd'] . shellescape(a:file)
    else
      let cmd = ['sh', '-c', a:config['cmd'] . shellescape(a:file)]
    endif

    let options = {'cfg': a:config, 'buf': '', 'file': a:file}
    if has_key(s:untracked_jobs, a:file)
      if job_status(get(s:untracked_jobs, a:file)) == 'run'
        return
      elseif has_key(s:untracked_jobs, a:file)
        call remove(s:untracked_jobs, a:file)
      endif
    endif
    let id = job_start(cmd, {
          \ 'err_io':   'out',
          \ 'out_cb':   function('s:on_stdout', options),
          \ 'close_cb': function('s:on_exit_untracked', options)})
    let s:untracked_jobs[a:file] = id
  endfunction

elseif has("nvim")
  " NVim specific functions

  function! s:nvim_untracked_job_handler(job_id, data, event) dict
    if a:event == 'stdout'
      let self.buf .=  join(a:data)
    else " on_exit handler
      call s:untracked_output(self, self.buf)
      if has_key(s:untracked_jobs, self.file)
        call remove(s:untracked_jobs, self.file)
      endif
    endif
  endfunction

  function! s:nvim_mq_job_handler(job_id, data, event) dict
    if a:event == 'stdout'
      let self.buf .=  join(a:data)
    else " on_exit handler
      call s:mq_output(self.buf, self.file)
    endif
  endfunction

  function! s:nvim_po_job_handler(job_id, data, event) dict
    if a:event == 'stdout'
      let self.buf .=  join(a:data)
    elseif a:event == 'stderr'
      let self.buf .=  join(a:data)
    else " on_exit handler
      call s:po_output(self.buf, self.file)
      call airline#extensions#po#shorten()
    endif
  endfunction

  function! airline#async#nvim_get_mq_async(cmd, file)
    let config = {
    \ 'buf': '',
    \ 'file': a:file,
    \ 'cwd': fnamemodify(a:file, ':p:h'),
    \ 'on_stdout': function('s:nvim_mq_job_handler'),
    \ 'on_exit': function('s:nvim_mq_job_handler')
    \ }
    if g:airline#init#is_windows && &shell =~ 'cmd'
      let cmd = a:cmd
    else
      let cmd = ['sh', '-c', a:cmd]
    endif

    if has_key(s:mq_jobs, a:file)
      call remove(s:mq_jobs, a:file)
    endif
    let id = jobstart(cmd, config)
    let s:mq_jobs[a:file] = id
  endfunction

  function! airline#async#nvim_get_msgfmt_stat(cmd, file)
    let config = {
    \ 'buf': '',
    \ 'file': a:file,
    \ 'cwd': fnamemodify(a:file, ':p:h'),
    \ 'on_stdout': function('s:nvim_po_job_handler'),
    \ 'on_stderr': function('s:nvim_po_job_handler'),
    \ 'on_exit': function('s:nvim_po_job_handler')
    \ }
    if g:airline#init#is_windows && &shell =~ 'cmd'
      " no msgfmt on windows?
      return
    else
      let cmd = ['sh', '-c', a:cmd. shellescape(a:file)]
    endif

    if has_key(s:po_jobs, a:file)
      call remove(s:po_jobs, a:file)
    endif
    let id = jobstart(cmd, config)
    let s:po_jobs[a:file] = id
  endfunction

endif

" Should work in either Vim pre 8 or Nvim
function! airline#async#nvim_vcs_untracked(cfg, file, vcs)
  let cmd = a:cfg.cmd . shellescape(a:file)
  let id = -1
  let config = {
  \ 'buf': '',
  \ 'vcs': a:vcs,
  \ 'cfg': a:cfg,
  \ 'file': a:file,
  \ 'cwd': fnamemodify(a:file, ':p:h')
  \ }
  if has("nvim")
    call extend(config, {
    \ 'on_stdout': function('s:nvim_untracked_job_handler'),
    \ 'on_exit': function('s:nvim_untracked_job_handler')})
    if has_key(s:untracked_jobs, config.file)
      " still running
      return
    endif
    let id = jobstart(cmd, config)
    let s:untracked_jobs[a:file] = id
  endif
  " vim without job feature or nvim jobstart failed
  if id < 1
    let output=system(cmd)
    call s:untracked_output(config, output)
    call airline#extensions#branch#update_untracked_config(a:file, a:vcs)
  endif
endfunction

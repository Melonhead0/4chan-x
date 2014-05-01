QR =
  mimeTypes: ['image/jpeg', 'image/png', 'image/gif', 'application/pdf', 'application/vnd.adobe.flash.movie', 'application/x-shockwave-flash', 'video/webm']

  init: ->
    return if !Conf['Quick Reply']

    @db = new DataBoard 'yourPosts'
    @posts = []

    if Conf['QR Shortcut']
      sc = $.el 'a',
        className: "qr-shortcut fa fa-comment-o #{unless Conf['Persistent QR'] then 'disabled' else ''}"
        textContent: 'QR' 
        title: 'Quick Reply'
        href: 'javascript:;'
      $.on sc, 'click', ->
        if Conf['Persistent QR'] or !QR.nodes or QR.nodes.el.hidden
          $.event 'CloseMenu'
          QR.open()
          QR.nodes.com.focus()
          $.rmClass @, 'disabled'
        else
          QR.close()
          $.addClass @, 'disabled'

      Header.addShortcut sc

    if Conf['Hide Original Post Form']
      $.asap (-> doc), -> $.addClass doc, 'hide-original-post-form'

    $.ready @initReady

    if Conf['Persistent QR']
      unless g.BOARD.ID is 'f' and g.VIEW is 'index'
        $.on d, '4chanXInitFinished', @persist
      else
        $.ready @persist

    Post.callbacks.push
      name: 'Quick Reply'
      cb:   @node

  initReady: ->
    QR.postingIsEnabled = !!$.id 'postForm'
    return unless QR.postingIsEnabled

    link = $.el 'h1',
      innerHTML: "<a href=javascript:; class='qr-link'>#{if g.VIEW is 'thread' then 'Reply to Thread' else 'Start a Thread'}</a>"
      className: "qr-link-container"
    
    QR.link = link.firstElementChild
    $.on link.firstChild, 'click', ->

      $.event 'CloseMenu'
      QR.open()
      QR.nodes.com.focus()
      if Conf['QR Shortcut']
        $.rmClass $('.qr-shortcut'), 'disabled'

    $.before $.id('togglePostForm') or $.id('postForm'), link

    $.on d, 'QRGetSelectedPost', ({detail: cb}) ->
      cb QR.selected
    $.on d, 'QRAddPreSubmitHook', ({detail: cb}) ->
      QR.preSubmitHooks.push cb

    <% if (type === 'crx') { %>
    $.on d, 'paste',              QR.paste
    <% } %>
    $.on d, 'dragover',           QR.dragOver
    $.on d, 'drop',               QR.dropFile
    $.on d, 'dragstart dragend',  QR.drag
    {
      catalog: ->
        QR.open() if Conf["Persistent QR"] 
        QR.hide() if Conf['Auto Hide QR']
      index: ->
        $.on d, 'IndexRefresh', QR.generatePostableThreadsList
      thread: ->
        $.on d, 'ThreadUpdate', QR.statusCheck
    }[g.VIEW]()

  statusCheck: ->
    if g.DEAD
      QR.abort()
    else
      QR.status()

  node: ->
    $.on $('a[title="Quote this post"]', @nodes.info), 'click', QR.quote

  persist: ->
    return unless QR.postingIsEnabled
    QR.open()
    QR.hide() if Conf['Auto Hide QR'] or g.VIEW is 'catalog'

  open: ->
    if QR.nodes
      QR.nodes.el.hidden = false
      QR.unhide()
      return
    try
      QR.dialog()
    catch err
      delete QR.nodes
      Main.handleErrors
        message: 'Quick Reply dialog creation crashed.'
        error: err
  close: ->
    if QR.req
      QR.abort()
      return
    QR.nodes.el.hidden = true
    QR.cleanNotifications()
    d.activeElement.blur()
    $.rmClass QR.nodes.el, 'dump'
    unless Conf['Captcha Warning Notifications']
      $.rmClass QR.captcha.nodes.input, 'error' if QR.captcha.isEnabled
    if Conf['QR Shortcut']
      $.toggleClass $('.qr-shortcut'), 'disabled'
    new QR.post true
    for post in QR.posts.splice 0, QR.posts.length - 1
      post.delete()
    QR.cooldown.auto = false
    QR.status()
    if QR.captcha.isEnabled and not Conf['Auto-load captcha']
      QR.captcha.destroy()
  focusin: ->
    $.addClass QR.nodes.el, 'focus'
  focusout: ->
    $.rmClass QR.nodes.el, 'focus'
  hide: ->
    d.activeElement.blur()
    $.addClass QR.nodes.el, 'autohide'
    QR.nodes.autohide.checked = true
  unhide: ->
    $.rmClass QR.nodes.el, 'autohide'
    QR.nodes.autohide.checked = false
  toggleHide: ->
    if @checked
      QR.hide()
    else
      QR.unhide()

  error: (err) ->
    QR.open()
    if typeof err is 'string'
      el = $.tn err
    else
      el = err
      el.removeAttribute 'style'
    if QR.captcha.isEnabled and /captcha|verification/i.test el.textContent
      if QR.captcha.captchas.length is 0
        # Focus the captcha input on captcha error.
        QR.captcha.nodes.input.focus()
        QR.captcha.setup()
      if Conf['Captcha Warning Notifications'] and !d.hidden
        QR.notify el
      else
        $.addClass QR.captcha.nodes.input, 'error'
        $.on QR.captcha.nodes.input, 'keydown', ->
          $.rmClass QR.captcha.nodes.input, 'error'
    else
      QR.notify el
    alert el.textContent if d.hidden

  notify: (el) ->
    notice = new Notice 'warning', el
    unless Header.areNotificationsEnabled and d.hidden
      QR.notifications.push notice
    else
      notif = new Notification el.textContent,
        body: el.textContent
        icon: Favicon.logo
      notif.onclick = -> window.focus()
      <% if (type === 'crx') { %>
      # Firefox automatically closes notifications
      # so we can't control the onclose properly.
      notif.onclose = -> notice.close()
      notif.onshow  = ->
        setTimeout ->
          notif.onclose = null
          notif.close()
        , 7 * $.SECOND
      <% } %>

  notifications: []
  cleanNotifications: ->
    for notification in QR.notifications
      notification.close()
    QR.notifications = []

  status: ->
    return unless QR.nodes
    {thread} = QR.posts[0]
    if thread isnt 'new' and g.threads["#{g.BOARD}.#{thread}"].isDead
      value    = 404
      disabled = true
      QR.cooldown.auto = false

    value = if QR.req
      QR.req.progress
    else
      QR.cooldown.seconds or value

    {status} = QR.nodes
    status.value = unless value
      'Submit'
    else if QR.cooldown.auto
      "Auto #{value}"
    else
      value
    status.disabled = disabled or false

  quote: (e) ->
    e?.preventDefault()
    return unless QR.postingIsEnabled

    sel   = d.getSelection()
    post  = Get.postFromNode @
    text  = ">>#{post}\n"
    if (s = sel.toString().trim()) and post is Get.postFromNode sel.anchorNode
      s = s.replace /\n/g, '\n>'
      text += ">#{s}\n"

    QR.open()
    if QR.selected.isLocked
      index = QR.posts.indexOf QR.selected
      (QR.posts[index+1] or new QR.post()).select()
      $.addClass QR.nodes.el, 'dump'
      QR.cooldown.auto = true
    {com, thread} = QR.nodes
    thread.value = Get.threadFromNode @ unless com.value

    caretPos = com.selectionStart
    # Replace selection for text.
    com.value = com.value[...caretPos] + text + com.value[com.selectionEnd..]
    # Move the caret to the end of the new quote.
    range = caretPos + text.length
    com.setSelectionRange range, range
    com.focus()

    QR.selected.save com
    QR.selected.save thread

    if Conf['QR Shortcut']
      $.rmClass $('.qr-shortcut'), 'disabled'

  characterCount: ->
    counter = QR.nodes.charCount
    count   = QR.nodes.com.textLength
    counter.textContent = count
    counter.hidden      = count < 1000
    (if count > 1500 then $.addClass else $.rmClass) counter, 'warning'

  drag: (e) ->
    # Let it drag anything from the page.
    toggle = if e.type is 'dragstart' then $.off else $.on
    toggle d, 'dragover', QR.dragOver
    toggle d, 'drop',     QR.dropFile

  dragOver: (e) ->
    e.preventDefault()
    e.dataTransfer.dropEffect = 'copy' # cursor feedback

  dropFile: (e) ->
    # Let it only handle files from the desktop.
    return unless e.dataTransfer.files.length
    e.preventDefault()
    QR.open()
    QR.handleFiles e.dataTransfer.files

  paste: (e) ->
    files = []
    for item in e.clipboardData.items when item.kind is 'file'
      blob = item.getAsFile()
      blob.name  = 'file'
      blob.name += '.' + blob.type.split('/')[1] if blob.type
      files.push blob
    return unless files.length
    QR.open()
    QR.handleFiles files
    $.addClass QR.nodes.el, 'dump'
    
  handleBlob: (urlBlob, contentType, contentDisposition, url) ->
    name = url.match(/([^\/]+)\/*$/)?[1]
    mime = contentType?.match(/[^;]*/)[0] or 'application/octet-stream'
    match =
      contentDisposition?.match(/\bfilename\s*=\s*"((\\"|[^"])+)"/i)?[1] or
      contentType?.match(/\bname\s*=\s*"((\\"|[^"])+)"/i)?[1]
    if match
      name = match.replace /\\"/g, '"'
    blob = new Blob([urlBlob], {type: mime})
    blob.name = name
    QR.handleFiles([blob])

  handleUrl:  ->
    url = prompt("Insert an url:")
    return if url is null

    <% if (type === 'crx') { %>
    xhr = new XMLHttpRequest();
    xhr.open('GET', url, true)
    xhr.responseType = 'blob'
    xhr.onload = (e) ->
      if @readyState is @DONE && xhr.status is 200
        contentType = @getResponseHeader('Content-Type')
        contentDisposition = @getResponseHeader('Content-Disposition')
        QR.handleBlob @response, contentType, contentDisposition, url
      else
        QR.error "Can't load image."
    xhr.onerror = (e) ->
      QR.error "Can't load image."
    xhr.send()
    <% } %>

    <% if (type === 'userscript') { %>
    GM_xmlhttpRequest
      method: "GET"
      url: url
      overrideMimeType: "text/plain; charset=x-user-defined"
      onload: (xhr) ->
        r = xhr.responseText
        data = new Uint8Array(r.length)
        i = 0
        while i < r.length
          data[i] = r.charCodeAt(i)
          i++
        contentType = xhr.responseHeaders.match(/Content-Type:\s*(.*)/i)?[1]
        contentDisposition = xhr.responseHeaders.match(/Content-Disposition:\s*(.*)/i)?[1]
        QR.handleBlob data, contentType, contentDisposition, url
      onerror: (xhr) ->
        QR.error "Can't load image."
    <% } %>

  handleFiles: (files) ->
    if @ isnt QR # file input
      files  = [@files...]
      @value = null
    return unless files.length
    QR.cleanNotifications()
    for file, i in files
      QR.handleFile file, i, files.length
    $.addClass QR.nodes.el, 'dump' unless files.length is 1

  handleFile: (file, index, nfiles) ->
    if /^text\//.test file.type
      if nfiles is 1
        post = QR.selected
      else if index isnt 0 or (post = QR.posts[QR.posts.length - 1]).com
        post = new QR.post()
      post.pasteText file
      return
    unless file.type in QR.mimeTypes
      QR.error "#{file.name}: Unsupported file type."
      return unless nfiles is 1
    max = QR.nodes.fileInput.max
    max = Math.min(max, QR.max_size_video) if /^video\//.test file.type
    if file.size > max
      QR.error "#{file.name}: File too large (file: #{$.bytesToString file.size}, max: #{$.bytesToString max})."
      return unless nfiles is 1
    isNewPost = false
    if nfiles is 1
      post = QR.selected
    else if index isnt 0 or (post = QR.posts[QR.posts.length - 1]).file
      isNewPost = true
      post = new QR.post()
    QR.checkDimensions file, (pass) ->
      if pass or nfiles is 1
        post.setFile file
      else if isNewPost
        post.rm()

  checkDimensions: (file, cb) ->
    if /^image\//.test file.type
      img = new Image()
      img.onload = =>
        {height, width} = img
        pass = true
        if height > QR.max_height or width > QR.max_width
          QR.error "#{file.name}: Image too large (image: #{height}x#{width}px, max: #{QR.max_height}x#{QR.max_width}px)"
          pass = false
        if height < QR.min_height or width < QR.min_width
          QR.error "#{file.name}: Image too small (image: #{height}x#{width}px, min: #{QR.min_height}x#{QR.min_width}px)"
          pass = false
        cb pass
      img.src = URL.createObjectURL file
    else if /^video\//.test file.type
      video = $.el 'video'
      $.on video, 'loadedmetadata', =>
        return unless cb?
        {videoHeight, videoWidth, duration} = video
        max_height = Math.min(QR.max_height, QR.max_height_video)
        max_width = Math.min(QR.max_width, QR.max_width_video)
        pass = true
        if videoHeight > max_height or videoWidth > max_width
          QR.error "#{file.name}: Video too large (video: #{videoHeight}x#{videoWidth}px, max: #{max_height}x#{max_width}px)"
          pass = false
        if videoHeight < QR.min_height or videoWidth < QR.min_width
          QR.error "#{file.name}: Video too small (video: #{videoHeight}x#{videoWidth}px, min: #{QR.min_height}x#{QR.min_width}px)"
          pass = false
        unless isFinite video.duration
          QR.error "#{file.name}: Video lacks duration metadata (try remuxing)"
          pass = false
        if duration > QR.max_duration_video
          QR.error "#{file.name}: Video too long (video: #{duration}s, max: #{QR.max_duration_video}s)"
          pass = false
        <% if (type === 'userscript') { %>
        if video.mozHasAudio
          QR.error "#{file.name}: Audio not allowed"
          pass = false
        <% } %>
        cb pass
        cb = null
      $.on video, 'error', =>
        return unless cb?
        if file.type in QR.mimeTypes
          # only report error here if we should have been able to play the video
          # otherwise "unsupported type" should already have been shown
          QR.error "#{file.name}: Video appears corrupt"
        cb false
        cb = null
      video.src = URL.createObjectURL file
    else
      cb true

  openFileInput: (e) ->
    e.stopPropagation()
    if e.shiftKey and e.type is 'click'
      return QR.selected.rmFile()
    if e.ctrlKey and e.type is 'click'
      $.addClass QR.nodes.filename, 'edit'
      QR.nodes.filename.focus()
      return $.on QR.nodes.filename, 'blur', -> $.rmClass QR.nodes.filename, 'edit'
    return if e.target.nodeName is 'INPUT' or (e.keyCode and e.keyCode not in [32, 13]) or e.ctrlKey
    e.preventDefault()
    QR.nodes.fileInput.click()

  generatePostableThreadsList: ->
    return unless QR.nodes
    list    = QR.nodes.thread
    options = [list.firstChild]
    for thread in g.BOARD.threads.keys
      options.push $.el 'option',
        value: thread
        textContent: "Thread No.#{thread}"
    val = list.value
    $.rmAll list
    $.add list, options
    list.value = val
    return unless list.value
    # Fix the value if the option disappeared.
    list.value = if g.VIEW is 'thread'
      g.THREADID
    else
      'new'

  dialog: ->
    QR.nodes = nodes =
      el: dialog = UI.dialog 'qr', 'top:0;right:0;', <%= importHTML('Features/QuickReply') %>

    nodes[key] = $ value, dialog for key, value of {
      move:       '.move'
      autohide:   '#autohide'
      thread:     'select'
      threadPar:  '#qr-thread-select'
      close:      '.close'
      form:       'form'
      dumpButton: '#dump-button'
      urlButton:  '#url-button'
      name:       '[data-name=name]'
      email:      '[data-name=email]'
      sub:        '[data-name=sub]'
      com:        '[data-name=com]'
      dumpList:   '#dump-list'
      addPost:    '#add-post'
      charCount:  '#char-count'
      fileSubmit: '#file-n-submit'
      filename:   '#qr-filename'
      fileContainer: '#qr-filename-container'
      fileRM:     '#qr-filerm'
      fileExtras: '#qr-extras-container'
      spoiler:    '#qr-file-spoiler'
      spoilerPar: '#qr-spoiler-label'
      status:     '[type=submit]'
      fileInput:  '[type=file]'
    }
    
    rules = $('ul.rules').textContent.trim()
    QR.min_width = QR.min_height = 1
    QR.max_width = QR.max_height = 10000
    try
      [_, QR.min_width, QR.min_height] = rules.match(/.+smaller than (\d+)x(\d+).+/)
      [_, QR.max_width, QR.max_height] = rules.match(/.+greater than (\d+)x(\d+).+/)
      for prop in ['min_width', 'min_height', 'max_width', 'max_height']
        QR[prop] = parseInt QR[prop], 10
    catch
      null

    nodes.fileInput.max = $('input[name=MAX_FILE_SIZE]').value

    QR.max_size_video = 3145728
    QR.max_width_video = QR.max_height_video = 2048
    QR.max_duration_video = 120

    QR.spoiler = !!$ 'input[name=spoiler]'
    if QR.spoiler
      $.addClass QR.nodes.el, 'has-spoiler'
    else
      nodes.spoiler.parentElement.hidden = true

    if g.BOARD.ID is 'f'
      nodes.flashTag = $.el 'select',
        name: 'filetag'
        innerHTML: """
          <option value=0>Hentai</option>
          <option value=6>Porn</option>
          <option value=1>Japanese</option>
          <option value=2>Anime</option>
          <option value=3>Game</option>
          <option value=5>Loop</option>
          <option value=4 selected>Other</option>
        """
      nodes.flashTag.dataset.default = '4'
      $.add nodes.form, nodes.flashTag

    QR.flagsInput()

    $.on nodes.filename.parentNode, 'click keydown', QR.openFileInput

    items = $$ '*', QR.nodes.el
    i = 0
    while elm = items[i++]
      $.on elm, 'blur',  QR.focusout
      $.on elm, 'focus', QR.focusin

    $.on nodes.autohide,   'change', QR.toggleHide
    $.on nodes.close,      'click',  QR.close
    $.on nodes.dumpButton, 'click',  -> nodes.el.classList.toggle 'dump'
    $.on nodes.urlButton,  'click',  QR.handleUrl
    $.on nodes.addPost,    'click',  -> new QR.post true
    $.on nodes.form,       'submit', QR.submit
    $.on nodes.fileRM,     'click', -> QR.selected.rmFile()
    $.on nodes.fileExtras, 'click', (e) -> e.stopPropagation()
    $.on nodes.spoiler,    'change', -> QR.selected.nodes.spoiler.click()
    $.on nodes.fileInput,  'change', QR.handleFiles

    # save selected post's data
    items = ['name', 'email', 'sub', 'com', 'filename', 'flag']
    i = 0
    save = -> QR.selected.save @
    while name = items[i++]
      continue unless node = nodes[name]
      event = if node.nodeName is 'SELECT' then 'change' else 'input'
      $.on nodes[name], event, save

    <% if (type === 'userscript') { %>
    if Conf['Remember QR Size']
      $.get 'QR Size', '', (item) ->
        nodes.com.style.cssText = item['QR Size']
      $.on nodes.com, 'mouseup', (e) ->
        return if e.button isnt 0
        $.set 'QR Size', @style.cssText
    <% } %>

    QR.generatePostableThreadsList()
    QR.persona.init()
    new QR.post true
    QR.status()
    QR.cooldown.init()
    QR.captcha.init()
    $.add d.body, dialog

    # Create a custom event when the QR dialog is first initialized.
    # Use it to extend the QR's functionalities, or for XTRM RICE.
    $.event 'QRDialogCreation', null, dialog

  flags: ->
    fn = (val) -> $.el 'option', 
      value: val[0]
      textContent: val[1]
    select = $.el 'select',
      name:      'flag'
      className: 'flagSelector'

    $.add select, fn flag for flag in [
      ['0',  'None']
      ['US', 'American']
      ['KP', 'Best Korean']
      ['BL', 'Black Nationalist']
      ['CM', 'Communist']
      ['CF', 'Confederate']
      ['RE', 'Conservative']
      ['EU', 'European']
      ['GY', 'Gay']
      ['PC', 'Hippie']
      ['IL', 'Israeli']
      ['DM', 'Liberal']
      ['RP', 'Libertarian']
      ['MF', 'Muslim']
      ['NZ', 'Nazi']
      ['OB', 'Obama']
      ['PR', 'Pirate']
      ['RB', 'Rebel']
      ['TP', 'Tea Partier']
      ['TX', 'Texan']
      ['TR', 'Tree Hugger']
      ['WP', 'White Supremacist']
    ]

    select

  flagsInput: ->
    {nodes} = QR
    return if not nodes
    if nodes.flag
      $.rm nodes.flag
      delete nodes.flag

    if g.BOARD.ID is 'pol'
      flag = QR.flags()
      flag.dataset.name    = 'flag'
      flag.dataset.default = '0'
      nodes.flag = flag
      $.add nodes.form, flag

  preSubmitHooks: []

  submit: (e) ->
    e?.preventDefault()

    if QR.req
      QR.abort()
      return

    if QR.cooldown.seconds
      QR.cooldown.auto = !QR.cooldown.auto
      QR.status()
      return

    post = QR.posts[0]
    post.forceSave()
    if g.BOARD.ID is 'f'
      filetag = QR.nodes.flashTag.value
    threadID = post.thread
    thread = g.BOARD.threads[threadID]

    # prevent errors
    if threadID is 'new'
      threadID = null
      if g.BOARD.ID is 'vg' and !post.sub
        err = 'New threads require a subject.'
      else unless post.file or textOnly = !!$ 'input[name=textonly]', $.id 'postForm'
        err = 'No file selected.'
    else if g.BOARD.threads[threadID].isClosed
      err = 'You can\'t reply to this thread anymore.'
    else unless post.com or post.file
      err = 'No file selected.'
    else if post.file and thread.fileLimit
      err = 'Max limit of image replies has been reached.'
    else for hook in QR.preSubmitHooks
      if err = hook post, thread
        break

    if QR.captcha.isEnabled and !err
      {challenge, response} = QR.captcha.getOne()
      err = 'No valid captcha.' unless response

    QR.cleanNotifications()
    if err
      # stop auto-posting
      QR.cooldown.auto = false
      QR.status()
      QR.error err
      return

    # Enable auto-posting if we have stuff to post, disable it otherwise.
    QR.cooldown.auto = QR.posts.length > 1
    if Conf['Auto Hide QR'] and !QR.cooldown.auto
      QR.hide()
    if !QR.cooldown.auto and $.x 'ancestor::div[@id="qr"]', d.activeElement
      # Unfocus the focused element if it is one within the QR and we're not auto-posting.
      d.activeElement.blur()

    post.lock()

    formData =
      resto:    threadID
      name:     post.name
      email:    post.email
      sub:      post.sub
      com:      post.com
      upfile:   post.file
      filetag:  filetag
      spoiler:  post.spoiler
      flag:     post.flag
      textonly: textOnly
      mode:     'regist'
      pwd:      QR.persona.pwd
      recaptcha_challenge_field: challenge
      recaptcha_response_field:  response

    options =
      responseType: 'document'
      withCredentials: true
      onload: QR.response
      onerror: (err, url, line) ->
        # Connection error, or www.4chan.org/banned
        delete QR.req
        post.unlock()
        QR.cooldown.auto = false
        QR.status()
        console.log err
        console.log url
        console.log line
        QR.error $.el 'span',
          innerHTML: """
          4chan X encountered an error while posting. 
          [<a href="//4chan.org/banned" target=_blank>Banned?</a>] [<a href="https://github.com/ccd0/4chan-x/wiki/Frequently-Asked-Questions#what-does-4chan-x-encountered-an-error-while-posting-please-try-again-mean" target=_blank>More info</a>]
          """
    extra =
      form: $.formData formData
      upCallbacks:
        onload: ->
          # Upload done, waiting for server response.
          QR.req.isUploadFinished = true
          QR.req.uploadEndTime    = Date.now()
          QR.req.progress = '...'
          QR.status()
        onprogress: (e) ->
          # Uploading...
          QR.req.progress = "#{Math.round e.loaded / e.total * 100}%"
          QR.status()

    QR.req = $.ajax "https://sys.4chan.org/#{g.BOARD}/post", options, extra
    # Starting to upload might take some time.
    # Provide some feedback that we're starting to submit.
    QR.req.uploadStartTime = Date.now()
    QR.req.progress = '...'
    QR.status()

  response: ->
    {req} = QR
    delete QR.req

    post = QR.posts[0]
    post.unlock()

    resDoc  = req.response
    if ban  = $ '.banType', resDoc # banned/warning
      board = $('.board', resDoc).innerHTML
      err   = $.el 'span', innerHTML:
        if ban.textContent.toLowerCase() is 'banned'
          """
          You are banned on #{board}! ;_;<br>
          Click <a href=//www.4chan.org/banned target=_blank>here</a> to see the reason.
          """
        else
          """
          You were issued a warning on #{board} as #{$('.nameBlock', resDoc).innerHTML}.<br>
          Reason: #{$('.reason', resDoc).innerHTML}
          """
    else if err = resDoc.getElementById 'errmsg' # error!
      $('a', err)?.target = '_blank' # duplicate image link
    else if resDoc.title isnt 'Post successful!'
      err = 'Connection error with sys.4chan.org.'
    else if req.status isnt 200
      err = "Error #{req.statusText} (#{req.status})"

    if err
      if /captcha|verification/i.test(err.textContent) or err is 'Connection error with sys.4chan.org.'
        # Remove the obnoxious 4chan Pass ad.
        if /mistyped/i.test err.textContent
          err = 'You seem to have mistyped the CAPTCHA.'
        else if /expired/i.test err.textContent
          err = 'This CAPTCHA is no longer valid because it has expired.'
        # Enable auto-post if we have some cached captchas.
        QR.cooldown.auto = if QR.captcha.isEnabled
          !!QR.captcha.captchas.length
        else if err is 'Connection error with sys.4chan.org.'
          true
        else
          # Something must've gone terribly wrong if you get captcha errors without captchas.
          # Don't auto-post indefinitely in that case.
          false
        # Too many frequent mistyped captchas will auto-ban you!
        # On connection error, the post most likely didn't go through.
        QR.cooldown.set delay: 2
      else if err.textContent and m = err.textContent.match /wait\s+(\d+)\s+second/i
        QR.cooldown.auto = if QR.captcha.isEnabled
          !!QR.captcha.captchas.length
        else
          true
        QR.cooldown.set delay: m[1]
      else # stop auto-posting
        QR.cooldown.auto = false
      QR.status()
      QR.error err
      return

    h1 = $ 'h1', resDoc
    QR.cleanNotifications()

    if Conf['Posting Success Notifications']
      QR.notifications.push new Notice 'success', h1.textContent, 5

    QR.persona.set post

    [_, threadID, postID] = h1.nextSibling.textContent.match /thread:(\d+),no:(\d+)/
    postID   = +postID
    threadID = +threadID or postID
    isReply  = threadID isnt postID

    QR.db.set
      boardID: g.BOARD.ID
      threadID: threadID
      postID: postID
      val: true

    ThreadUpdater.postID = postID

    # Post/upload confirmed as successful.
    $.event 'QRPostSuccessful', {
      board: g.BOARD
      threadID
      postID
    }
    $.event 'QRPostSuccessful_', {threadID, postID}

    # Enable auto-posting if we have stuff left to post, disable it otherwise.
    postsCount = QR.posts.length - 1
    QR.cooldown.auto = postsCount and isReply
    if QR.cooldown.auto and QR.captcha.isEnabled and (captchasCount = QR.captcha.captchas.length) < 3 and captchasCount < postsCount
      notif = new Notification 'Quick reply warning',
        body: "You are running low on cached captchas. Cache count: #{captchasCount}."
        icon: Favicon.logo
      notif.onclick = ->
        QR.open()
        QR.captcha.nodes.input.focus()
        window.focus()
      notif.onshow = ->
        setTimeout ->
          notif.close()
        , 7 * $.SECOND

    unless Conf['Persistent QR'] or QR.cooldown.auto
      QR.close()
    else
      if QR.posts.length > 1 and QR.captcha.isEnabled and QR.captcha.captchas.length is 0
        QR.captcha.setup()
      post.rm()

    QR.cooldown.set {req, post, isReply, threadID}

    URL = if threadID is postID # new thread
      "/#{g.BOARD}/thread/#{threadID}"
    else if g.VIEW is 'index' and !QR.cooldown.auto and Conf['Open Post in New Tab'] # replying from the index
      "/#{g.BOARD}/thread/#{threadID}#p#{postID}"
    if URL
      if Conf['Open Post in New Tab']
        $.open URL
      else
        window.location = URL

    QR.status()

  abort: ->
    if QR.req and !QR.req.isUploadFinished
      QR.req.abort()
      delete QR.req
      QR.posts[0].unlock()
      QR.cooldown.auto = false
      QR.notifications.push new Notice 'info', 'QR upload aborted.', 5
    QR.status()

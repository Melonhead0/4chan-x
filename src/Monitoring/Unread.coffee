Unread =
  init: ->
    return if g.VIEW isnt 'thread' or
      !Conf['Unread Count'] and
      !Conf['Unread Favicon'] and
      !Conf['Unread Line'] and
      !Conf['Scroll to Last Read Post'] and
      !Conf['Thread Watcher'] and
      !Conf['Desktop Notifications'] and
      !Conf['Quote Threading']

    @db = new DataBoard 'lastReadPosts', @sync
    @hr = $.el 'hr',
      id: 'unread-line'
    @posts = new Set
    @postsQuotingYou = new Set
    @order = new RandomAccessList
    @position = null

    Thread.callbacks.push
      name: 'Unread'
      cb:   @node
    Post.callbacks.push
      name: 'Unread'
      cb:   @addPost

    <% if (tests_enabled) { %>
    testLink = $.el 'a',
      textContent: 'Test Post Order'
    $.on testLink, 'click', ->
      list1 = (x.ID for x in Unread.order.order())
      list2 = (+x.id[2..] for x in $$ '.postContainer')
      pass = do ->
        return false unless list1.length is list2.length
        for i in [0...list1.length] by 1
          return false if list1[i] isnt list2[i]
        true
      if pass
        new Notice 'success', "Orders same (#{list1.length} posts)", 5
      else
        new Notice 'warning', 'Orders differ.', 30
        c.log list1
        c.log list2
    Header.menu.addEntry
      el: testLink
    <% } %>

  node: ->
    Unread.thread = @
    Unread.title  = d.title
    Unread.lastReadPost = Unread.db.get
      boardID: @board.ID
      threadID: @ID
      defaultValue: 0
    Unread.readCount = 0
    Unread.readCount++ for ID in @posts.keys when +ID <= Unread.lastReadPost
    $.one d, '4chanXInitFinished',      Unread.ready
    $.on  d, 'ThreadUpdate',            Unread.onUpdate
    $.on  d, 'scroll visibilitychange', Unread.read
    $.on  d, 'visibilitychange',        Unread.setLine if Conf['Unread Line']

  ready: ->
    Unread.setLine true
    Unread.read()
    Unread.update()
    Unread.scroll() if Conf['Scroll to Last Read Post']

  positionPrev: ->
    if Unread.position then Unread.position.prev else Unread.order.last

  scroll: ->
    # Let the header's onload callback handle it.
    return if (hash = location.hash.match /\d+/) and hash[0] of Unread.thread.posts

    position = Unread.positionPrev()
    while position
      {root} = position.data.nodes
      if !root.getBoundingClientRect().height
        # Don't try to scroll to posts with display: none
        position = position.prev
      else
        Header.scrollToIfNeeded root, true
        break
    return

  sync: ->
    return unless Unread.lastReadPost?
    lastReadPost = Unread.db.get
      boardID: Unread.thread.board.ID
      threadID: Unread.thread.ID
      defaultValue: 0
    return unless Unread.lastReadPost < lastReadPost
    Unread.lastReadPost = lastReadPost

    postIDs = Unread.thread.posts.keys
    for i in [Unread.readCount...postIDs.length] by 1
      ID = +postIDs[i]
      unless Unread.thread.posts[ID].isFetchedQuote
        break if ID > Unread.lastReadPost
        Unread.posts.delete ID
        Unread.postsQuotingYou.delete ID
      Unread.readCount++

    Unread.updatePosition()
    Unread.setLine()
    Unread.update()

  addPost: ->
    return if @isFetchedQuote or @isClone
    Unread.order.push @
    return if @ID <= Unread.lastReadPost or @isHidden or QR.db?.get {
      boardID:  @board.ID
      threadID: @thread.ID
      postID:   @ID
    }
    Unread.posts.add @ID
    Unread.addPostQuotingYou @
    Unread.position ?= Unread.order[@ID]

  addPostQuotingYou: (post) ->
    for quotelink in post.nodes.quotelinks when QR.db?.get Get.postDataFromLink quotelink
      Unread.postsQuotingYou.add post.ID
      Unread.openNotification post
      return

  openNotification: (post) ->
    return unless Header.areNotificationsEnabled
    notif = new Notification "#{post.info.nameBlock} replied to you",
      body: post.info[if Conf['Remove Spoilers'] or Conf['Reveal Spoilers'] then 'comment' else 'commentSpoilered']
      icon: Favicon.logo
    notif.onclick = ->
      Header.scrollToIfNeeded post.nodes.root, true
      window.focus()
    notif.onshow = ->
      setTimeout ->
        notif.close()
      , 7 * $.SECOND

  onUpdate: (e) ->
    if !e.detail[404]
      Unread.setLine()
      Unread.read()
    Unread.update()

  readSinglePost: (post) ->
    {ID} = post
    return unless Unread.posts.has ID
    Unread.posts.delete ID
    Unread.postsQuotingYou.delete ID
    Unread.updatePosition()
    Unread.saveLastReadPost()
    Unread.update()

  read: $.debounce 100, (e) ->
    return if d.hidden or !Unread.posts.size
    height  = doc.clientHeight

    count = 0
    while Unread.position
      {ID, data} = Unread.position
      {root} = data.nodes
      break unless !root.getBoundingClientRect().height or # post has been hidden
        Header.getBottomOf(root) > -1                      # post is completely read
      count++
      Unread.posts.delete ID
      Unread.postsQuotingYou.delete ID

      if Conf['Mark Quotes of You'] and QR.db?.get {
        boardID:  data.board.ID
        threadID: data.thread.ID
        postID:   ID
      }
        QuoteYou.lastRead = root
      Unread.position = Unread.position.next

    return unless count
    Unread.updatePosition()
    Unread.saveLastReadPost()
    Unread.update() if e

  updatePosition: ->
    while Unread.position and !Unread.posts.has Unread.position.ID
      Unread.position = Unread.position.next

  saveLastReadPost: $.debounce 2 * $.SECOND, ->
    postIDs = Unread.thread.posts.keys
    for i in [Unread.readCount...postIDs.length] by 1
      ID = +postIDs[i]
      unless Unread.thread.posts[ID].isFetchedQuote
        break if Unread.posts.has ID
        Unread.lastReadPost = ID
      Unread.readCount++
    return if Unread.thread.isDead and !Unread.thread.isArchived
    Unread.db.forceSync()
    Unread.db.set
      boardID:  Unread.thread.board.ID
      threadID: Unread.thread.ID
      val:      Unread.lastReadPost

  setLine: (force) ->
    return unless Conf['Unread Line']
    if d.hidden or (force is true)
      if Unread.linePosition = Unread.positionPrev()
        $.after Unread.linePosition.data.nodes.root, Unread.hr
      else
        $.rm Unread.hr
    Unread.hr.hidden = Unread.linePosition is Unread.order.last

  update: ->
    count = Unread.posts.size
    countQuotingYou = Unread.postsQuotingYou.size

    if Conf['Unread Count']
      titleQuotingYou = if Conf['Quoted Title'] and countQuotingYou then '(!) ' else ''
      titleCount = if count or !Conf['Hide Unread Count at (0)'] then "(#{count}) " else ''
      titleDead = if Unread.thread.isDead
        Unread.title.replace '-', (if Unread.thread.isArchived then '- Archived -' else '- 404 -')
      else
        Unread.title
      d.title = "#{titleQuotingYou}#{titleCount}#{titleDead}"

    return unless Conf['Unread Favicon']

    Favicon.el.href =
      if Unread.thread.isDead
        if countQuotingYou
          Favicon.unreadDeadY
        else if count
          Favicon.unreadDead
        else
          Favicon.dead
      else
        if count
          if countQuotingYou
            Favicon.unreadY
          else
            Favicon.unread
        else
          Favicon.default

    <% if (type === 'userscript') { %>
    # `favicon.href = href` doesn't work on Firefox.
    $.add d.head, Favicon.el
    <% } %>

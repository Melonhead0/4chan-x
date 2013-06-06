Linkify =
  init: ->
    return if g.VIEW is 'catalog' or !Conf['Linkification']
    @catchAll = /(?:(?:([a-z]+)(?::|%[0-9a-fA-F]{2}))?(?:(?:(?:\?|%[0-9a-fA-F]{2})xt(?:=|%[0-9a-fA-F]{2})urn(?::|%[0-9a-fA-F]{2})[^\s<>]*)|(?:\/{2}|(?:%[0-9a-fA-F]{2}){2})?(?:\b\S+(?::\S*)?(@))?(?:(?!10(?:\.\d{1,3}){3})(?!127(?:\.\d{1,3}){3})(?!169\.254(?:\.\d{1,3}){2})(?!192\.168(?:\.\d{1,3}){2})(?!172\.(?:1[6-9]|2\d|3[0-1])(?:\.\d{1,3}){2})(?:[1-9]\d?|1\d\d|2[01]\d|22[0-3])(?:\.(?:1?\d{1,2}|2[0-4]\d|25[0-5])){2}(?:\.(?:[1-9]\d?|1\d\d|2[0-4]\d|25[0-4]){1,3})|(?:\b)([a-zA-Z\u00a1-\uffff0-9][a-zA-Z\u00a1-\uffff0-9\-\.]+)(\.[a-z\u00a1-\uffff0-9]{2,})))(?::\d{2,5})?((?:[\/#]|%[0-9a-fA-F]{2})[^\s<>]*)?)/i

    @tld = /^(?:a(?:e(?:ro)?|r(?:pa)?|s(?:ia)?|[cdfgilmnoqtuwxz])|b(?:iz?|[abdefghjmnorstvwyz])|c(?:at?|o(?:(?:op|m))?|[cdfghiklmnrsuvxyz])|i(?:n(?:(?:fo|t))?|[delmoqrst])|j(?:o(?:bs)?|[emp])|m(?:o(?:bi)?|u(?:seum)?|il|[acdeghklmnpqrstvwxyz])|n(?:a(?:me)?|et?|[cfgilopruz])|o(?:rg|m)|p(?:ost|ro?|[aefghklmnstwy])|t(?:el|r(?:avel)?|[cdfghjklmnoptvwz])|xxx|e(?:du|[ceghrstu])|g(?:ov|[abdefghilmnpqrstuwy])|d[dejkmoz]|f[ijkmor]|h[kmnrtu]|k[eghimnprwyz]|l[abcikrstuvy]|qa|r[eosuw]|s[abcdeghijklmnorstuvxyz]|u[agksyz]|v[aceginu]|w[fs]|y[etu]|z[amw])$/

    @globalCatchAll = new RegExp @catchAll.source, 'g'

    Post::callbacks.push
      name: 'Linkification'
      cb:   @node

  node: ->
    return if @isClone or @isHidden or @thread.isHidden or !links = @info.comment.match Linkify.globalCatchAll

    for link in links
      [link, protocol, isEmail, domain, tld, resource] = link.match Linkify.catchAll
      if /\.{2}|-{2}|w{3}\.4chan\.org/.test domain + tld
        # https://code.google.com/p/chromium/issues/detail?id=146162
        # V8 doesn't like complex regex it seems.
        continue
      if tld and !isEmail and !resource
        if !Linkify.tld.test pastDot = tld[1..]
          continue
        if @board.ID is 'g' and /^p[ly]|sh$/.test pastDot
          continue

      if !protocol and isEmail and resource
        link = link[...-resource.length]

      link = Linkify.trim link
      if /\)$/.test(link) and close = link.match /\)/g
        open = link.match(/\(/g) or ''
        if close.length > open.length
          link = Linkify.trim link[...-close.length - open.length]

      try
        URI = decodeURIComponent link
        if protocol is 'magnet'
          URI = link
      catch err
        continue

      if !protocol and !isEmail
        subdomain = URI.match(/^[a-z]+(?=\.)/)?[0]

      href = if protocol
        [URI, protocol is 'magnet']
      else if isEmail
        ["mailto:#{URI}", true]
      else if /^ftps?|irc$/.test subdomain
        ["#{subdomain}://#{URI}", subdomain is 'irc']
      else
        ["http://#{URI}"]

      Linkify.href    = href
      Linkify.link    = link
      Linkify.length  = link.length
      Linkify.seeking = false
      Linkify.found   = false
      Linkify.nodes   = []

      for child in @nodes.comment.childNodes
        Linkify.seek child
        break if Linkify.found
    return

  seek: (node) ->
    return unless node

    switch node.localName or node.nodeName
      when '#text'
        break
      when 'wbr'
        if @seeking
          @container.nodes.push node
        return
      when 's'
        return if $$('s', node).length
        if (nodes = node.childNodes).length is 1
          node = node.firstChild
          inSpoiler = true
          break
        if node.textContent.length >= @length
          for child in nodes
            @seek child
            break if @found
        return
      when 'span'
        for child in node.childNodes
          @seek child
          break if @found
        return
      else
        return
    if @seeking
      @current += node.data
      if inSpoiler
        if Conf['Clean Links']
          $.replace node.parentNode, node
        else
          node = node.parentNode
      if @length > @current.length
        @container.nodes.push node
        return
      if after = @current[@length...]
        node.data = node.data[...-after.length]
      @container.nodes.push node
      a = Linkify.anchor @href
      $.add a, @container.nodes
      @nodes.push a
      @nodes.push $.tn after if after
      $.replace @container.entry, @nodes
      @found = true
      return

    unless data = node.data
      return

    if (index = data.indexOf @link) >= 0
      if inSpoiler
        node = node.parentNode
      if index
        @nodes.push $.tn data[...index]
      a = Linkify.anchor @href
      a.textContent = @link
      @nodes.push a
      if data = data[index + @length..]
        @nodes.push $.tn data
      $.replace node, @nodes
      @found = true
      return

    return unless next = node.nextSibling
    if next.localName is 'wbr'
      next = next.nextSibling
    return if next.localName is 'a' or !nextData = next.textContent
    index = 0
    while index isnt data.length
      start = data[index++..]
      if @link[...start.length] is start
        index--
        break
    guess = start + nextData
    return unless start and @link[...guess.length] is guess or guess.indexOf(@link) >=0

    if index
      @nodes.push $.tn data[...index]
      node.data = start

    if inSpoiler
      if Conf['Clean Links']
        $.replace node.parentNode, node
      else
        node = node.parentNode
    @container =
      nodes: [node.cloneNode true]
      entry: node
    @current = start
    @seeking = true

  anchor: (href) ->
    [URI, thisTab] = href
    $.el 'a',
      target: if thisTab then '' else '_blank'
      rel:    'noreferrer'
      href:   URI

  trim: (link) ->
    if close = link.match /["',;\]?.]+$/
      link[...close.index]
    else
      link

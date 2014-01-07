Redirect =

  init: ->
    o =
      thread: {}
      post:   {}
      file:   {}

    {archives} = Redirect

    for boardID, data of Conf['selectedArchives']
      for type, id of data when (archive = archives[id]) and boardID in (archive[type] or archive['boards'])
        o[type][boardID] = archive

    for name, archive of archives
      for boardID in archive.boards
        unless boardID of o.thread
          o.thread[boardID] = archive
        unless boardID of o.post or archive.software isnt 'foolfuuka'
          o.post[boardID] = archive
        unless boardID of o.file or boardID not in archive.files
          o.file[boardID] = archive
    
    Redirect.data = o

  archives:
    "Foolz":
      domain: "archive.foolz.us"
      http:  false
      https: true
      software: "foolfuuka"
      boards: ["a", "co", "gd", "jp", "m", "sp", "tg", "tv", "v", "vg", "vp", "vr", "wsg"]
      files:  ["a", "gd", "jp", "m", "tg", "vg", "vp", "vr", "wsg"]

    "NSFW Foolz":
      domain: "nsfw.foolz.us"
      http:  false
      https: true
      software: "foolfuuka"
      boards: ["u"]
      files:  ["u"]

    "The Dark Cave":
      domain: "archive.thedarkcave.org"
      http:  true
      https: true
      software: "foolfuuka"
      boards: ["c", "int", "out", "po"]
      files:  ["c", "po"]

    "4plebs":
      domain: "archive.4plebs.org"
      http:  true
      https: true
      software: "foolfuuka"
      boards: ["hr", "pol", "s4s", "tg", "tv", "x"]
      files:  ["hr", "pol", "s4s", "tg", "tv", "x"]

    "Nyafuu":
      domain: "archive.nyafuu.org"
      http:  true
      https: true
      software: "foolfuuka"
      boards: ["c", "w", "wg"]
      files:  ["c", "w", "wg"]

    "Install Gentoo":
      domain: "archive.installgentoo.net"
      http:  false
      https: true
      software: "fuuka"
      boards: ["diy", "g", "sci"]
      files:  []

    "Rebecca Black Tech":
      domain: "rbt.asia"
      http:  true
      https: true
      software: "fuuka"
      boards: ["cgl", "g", "mu", "w"]
      files:  ["cgl", "g", "mu", "w"]

    "Heinessen":
      domain: "archive.heinessen.com"
      http: true
      software: "fuuka"
      boards: ["an", "fit", "k", "mlp", "r9k", "toy"]
      files:  ["an", "fit", "k", "r9k", "toy"]

    "warosu":
      domain: "fuuka.warosu.org"
      http:  true
      https: true
      software: "fuuka"
      boards: ["3", "cgl", "ck", "fa", "ic", "jp", "lit", "tg", "vr"]
      files:  ["3", "cgl", "ck", "fa", "ic", "jp", "lit", "tg", "vr"]

    "Bui's Archive":
      domain: "archive.bui.pm"
      http:  true
      https: true
      software: "foolfuuka"
      boards: ["b"]
      files:  ["b"]

    "Foolz Beta":
      domain: "beta.foolz.us"
      http:  true
      https: true
      withCredentials: true
      software: "foolfuuka"
      boards: ["a", "co", "d", "gd", "h", "jp", "m", "mlp", "sp", "tg", "tv", "u", "v", "vg", "vp", "vr", "wsg"],
      files:  ["a", "d", "gd", "h", "jp", "m", "tg", "u", "vg", "vp", "vr", "wsg"]

  to: (dest, data) ->
    archive = (if dest is 'search' then Redirect.data.thread else Redirect.data[dest])[data.boardID]
    return '' unless archive
    Redirect[dest] archive, data

  protocol: (archive) ->
    protocol = location.protocol
    unless archive[protocol[0...-1]]
      protocol = if protocol is 'https:' then 'http:' else 'https:'
    "#{protocol}//"

  thread: (archive, {boardID, threadID, postID}) ->
    # Keep the post number only if the location.hash was sent f.e.
    path = if threadID
      "#{boardID}/thread/#{threadID}"
    else
      "#{boardID}/post/#{postID}"
    if archive.software is 'foolfuuka'
      path += '/'
    if threadID and postID
      path += if archive.software is 'foolfuuka'
        "##{postID}"
      else
        "#p#{postID}"
    "#{Redirect.protocol archive}#{archive.domain}/#{path}"

  post: (archive, {boardID, postID}) ->
    # For fuuka-based archives:
    # https://github.com/eksopl/fuuka/issues/27
    URL = new String "#{Redirect.protocol archive}#{archive.domain}/_/api/chan/post/?board=#{boardID}&num=#{postID}"
    URL.archive = archive
    URL

  file: (archive, {boardID, filename}) ->
    "#{Redirect.protocol archive}#{archive.domain}/#{boardID}/full_image/#{filename}"

  search: (archive, {boardID, type, value}) ->
    type = if type is 'name'
      'username'
    else if type is 'MD5'
      'image'
    else
      type
    value = encodeURIComponent value
    path  = if archive.software is 'foolfuuka'
      "#{boardID}/search/#{type}/#{value}"
    else
      "#{boardID}/?task=search2&search_#{if type is 'image' then 'media_hash' else type}=#{value}"
    "#{Redirect.protocol archive}#{archive.domain}/#{path}"

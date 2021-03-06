FileInfo =
  init: ->
    return if g.VIEW is 'catalog' or !Conf['File Info Formatting']

    Post.callbacks.push
      name: 'File Info Formatting'
      cb:   @node
  node: ->
    return if !@file or @isClone
    $.extend @file.text, <%= html('<span class="file-info"></span>') %>
    FileInfo.format Conf['fileInfo'], @, @file.text.firstElementChild
  format: (formatString, post, outputNode) ->
    output = []
    formatString.replace /%(.)|[^%]+/g, (s, c) ->
      output.push if c of FileInfo.formatters
        FileInfo.formatters[c].call post
      else
        <%= html('${s}') %>
      ''
    $.extend outputNode, <%= html('@{output}') %>
  formatters:
    t: -> <%= html('${this.file.URL.match(/\\d+\\..+$/)[0]}') %>
    T: -> <%= html('<a href="${this.file.URL}" target="_blank">&{FileInfo.formatters.t.call(this)}</a>') %>
    l: -> <%= html('<a href="${this.file.URL}" target="_blank">&{FileInfo.formatters.n.call(this)}</a>') %>
    L: -> <%= html('<a href="${this.file.URL}" target="_blank">&{FileInfo.formatters.N.call(this)}</a>') %>
    n: ->
      fullname  = @file.name
      shortname = Build.shortFilename @file.name, @isReply
      if fullname is shortname
        <%= html('${fullname}') %>
      else
        <%= html('<span class="fnswitch"><span class="fntrunc">${shortname}</span><span class="fnfull">${fullname}</span></span>') %>
    N: -> <%= html('${this.file.name}') %>
    p: -> if @file.isSpoiler then <%= html('Spoiler, ') %> else <%= html('') %>
    s: -> <%= html('${this.file.size}') %>
    B: -> <%= html('${Math.round(this.file.sizeInBytes)} Bytes') %>
    K: -> <%= html('${Math.round(this.file.sizeInBytes/1024)} KB') %>
    M: -> <%= html('${Math.round(this.file.sizeInBytes/1048576*100)/100} MB') %>
    r: -> <%= html('${this.file.dimensions || "PDF"}') %>
    '%': -> <%= html('%') %>

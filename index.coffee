https = require 'https'
events = require 'events'

module.exports = class Librato extends events.EventEmitter
  @HOST: 'metrics-api.librato.com',
  @PATH: '/v1/metrics'
  @METHOD: 'POST'

  constructor: (@user, @key, @source, flushFrequency = 60000, maxRecords = 300) ->
    @cache = new Cache flushFrequency, maxRecords

    process.once 'exit', @shutdown.bind(@)
    @cache.on 'flush', (data) =>
      @_flush data, (err) =>
        @emit 'error', err if err
        process.exit() if @shuttingDown

  report: (name, value) ->
    data = @_mergeDefaults {name, value}
    @cache.push data

  shutdown: ->
    @shuttingDown = true
    @cache.shutdown()

  _mergeDefaults: (data) ->
    data.measure_time = Math.floor Date.now() / 1000
    data.source = @source
    data

  _flush: (gauges, callback) ->
    if gauges.length > 0
      @_request {gauges}, (err) -> callback? err
    else
      setImmediate callback

  _request: (data, callback) ->
    body = JSON.stringify data

    args =
      method: Librato.METHOD
      hostname: Librato.HOST
      path: Librato.PATH
      auth: "#{@user}:#{@key}"
      headers:
        'content-type': 'application/json'
        'content-length': Buffer.byteLength body

    req = https.request args, (res) ->
      res.on 'data', ->
      res.on 'error', callback
      res.on 'end', callback
      if res.statusCode >= 300
        callback new Error "Response code #{res.statusCode}"
        callback = ->

    req.on('error', callback).end(body)



class Cache extends events.EventEmitter
  constructor: (@minFrequency, @maxRecords) ->
    super()

    @lastFlushedAt = Date.now()
    @reset()

    @on 'push', =>
      @flush() if @records.length > @maxRecords

  reset: ->
    @records = []

    clearInterval @timer
    @timer = setInterval =>
      @flush()
    , @minFrequency

  push: (record) ->
    @records.push record
    @emit 'push'

  flush: ->
    @emit 'flush', @records
    @reset()

  shutdown: ->
    clearInterval @timer
    setImmediate =>
      @emit 'flush', @records

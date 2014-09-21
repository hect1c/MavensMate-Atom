_     = require 'underscore-plus'
util  = require '../mavensmate-util'

class CommandParser
  
  obj:
    message: null
    indicator: null
    stackTrace: null
    result: null
    isException: false

  constructor: (@command, @params, @result) ->
    @obj.result = result

  parse: ->
    if @result.body? and @result.success?
      @obj.message = @result.body
      @obj.indicator = if @result.success then 'success' else 'danger'
      @obj.stackTrace = @result.stackTrace
      @obj.isException = @result.stackTrace?
    else if @result.body? and not @result.sucess
      @obj = @getErrorOutput()
    else
      @obj.message = 'Unable to parse the command\'s result. This really should not happen, so please generate a log and create a GitHub issue (please search before creating new issues!)'
      @obj.indicator = 'warning'
      @obj.stackTrace = @result.stackTrace
      @obj.isException = @result.stackTrace?

    return @obj

  getErrorOutput: ->
    output =
      message: @result.body
      indicator: 'danger'
      stackTrace: @result.stackTrace
      isException: @result.stackTrace?

class GetOrgWideTestCoverageParser extends CommandParser

  parse: ->
    @obj.indicator = 'info'
    @obj.message = "Total Apex Unit Test Coverage: #{@result.PercentCovered}%"
    return @obj

class DeleteParser extends CommandParser

  parse: ->
    if @result.success
      @obj.indicator = "success"
      if @params.payload.files? and @params.payload.files.length is 1
        @obj.message = 'Deleted ' + util.baseName(@params.payload.files[0])
      else
        @obj.message = "Deleted selected metadata"
      return @obj
    else
      @getErrorOutput @params, @result

class UiParser extends CommandParser

  parse: ->
    if @result.success
      @obj.message = 'UI generated successfully'
      @obj.indicator = 'success'
      return @obj
    else
      return @getErrorOutput @params, @result

class CompileParser extends CommandParser

  parse: ->
    filesCompiled = {}
    for filePath in @params.payload.files
      fileNameBase = util.baseName(filePath)
      fileNameWithoutExtension = util.withoutExtension(fileNameBase)
      compiledFile = {}
      compiledFile.filePath = filePath
      compiledFile.fileNameWithoutExtension = fileNameWithoutExtension
      compiledFile.fileNameBase = fileNameBase
      filesCompiled[fileNameWithoutExtension] = compiledFile

      atom.project.errors[filePath] = []

    for filePath, errors of atom.project.errors
      fileNameBase = util.baseName(filePath)
      fileNameWithoutExtension = util.withoutExtension(fileNameBase)

      if not filesCompiled[fileNameWithoutExtension]?
        compiledFile = {}
        compiledFile.filePath = filePath
        compiledFile.fileNameWithoutExtension = fileNameWithoutExtension
        compiledFile.fileNameBase = fileNameBase
        filesCompiled[fileNameWithoutExtension] = compiledFile

    errorsByFilePath = {}  

    if @result.State? # tooling
      if @result.state is 'Error' and @result.ErrorMsg?
        @obj.message = @result.ErrorMsg
        @obj.success = false
      else if @result.State is 'Failed' and @result.CompilerErrors?
        if Object.prototype.toString.call @result.CompilerErrors is '[object String]'
          @result.CompilerErrors = JSON.parse @result.CompilerErrors

        errors = @result.CompilerErrors
        message = 'Compile Failed'
        for error in errors
          if filesCompiled[error.name]?
            error.fileName = filesCompiled[error.name].fileNameBase
            error.filePath = filesCompiled[error.name].filePath
          else            
            error.fileName = error.name
            error.filePath = error.name
          if error.line?
            errorMessage = "#{error.fileName}: #{error.problem[0]} (Line: #{error.line[0]})"
            error.lineNumber = error.line[0]
          else
            errorMessage = "#{error.fileName}: #{error.problem}"
          message += '<br/>' + errorMessage

          errorsByFilePath[error.filePath] ?= []
          errorsByFilePath[error.filePath].push(error)
        @obj.message = message
        @obj.indicator = 'danger'        
      else if @result.State is 'Failed' and @result.DeployDetails?
        errors = @result.DeployDetails.componentFailures
        message = 'Compile Failed'
        for error in errors
          errorName = error.fileName || error.fullName || error.name
          if filesCompiled[errorName]?
            error.fileName = filesCompiled[errorName].fileNameBase
            error.filePath = filesCompiled[errorName].filePath
          else         
            error.fileName = errorName
            error.filePath = errorName
          if error.lineNumber
            errorMessage = "#{error.fileName}: #{error.problem} (Line: #{error.lineNumber})"
          else
            errorMessage = "#{error.fileName}: #{error.problem}"
          message += '<br/>' + errorMessage

          errorsByFilePath[error.filePath] ?= []
          errorsByFilePath[error.filePath].push(error)

        @obj.message = message
        @obj.indicator = 'danger'
      else if @result.State is 'Completed' and not @result.ErrorMsg
        @obj.indicator = 'success'
        @obj.message = 'Success'
      else
        #pass
    else if @result.actions?
      # need to diff
      @obj.message = @result.body
      @obj.indicator = 'warning'
    # else # metadata api
    #   #todo
    for filePath, errors of errorsByFilePath
      fileNameBase = util.baseName(filePath)
      fileNameWithoutExtension = util.withoutExtension(fileNameBase)
      if atom.project.errors[fileNameWithoutExtension]?
        delete atom.project.errors[fileNameWithoutExtension]
      atom.project.errors[filePath] = errors
    if !@obj.message?
      throw 'unable to parse'

    return @obj

class CompileProjectParser extends CommandParser

  parse: ->
    if @result.success?
      atom.project.errors = {}
      @obj.success = @result.success;
      if @result.success
        @obj.message = "Success"
        @obj.indicator = 'success'
        emitter.emit 'mavensmate:compile-success-buffer-notify', @params
      else
        if @result.Messages?
          errors = @result.Messages
          @obj.indicator = 'danger'

          message = 'Compile Project Failed'
          for error in errors
            error.returnedPath = error.fileName
            error.fileName = util.baseName(error.returnedPath)
            treePath = './' + error.returnedPath.replace('unpackaged', 'src')
            error.filePath = atom.project.resolve(treePath)
            if error.lineNumber? and error.columnNumber?
              errorMessage = "#{error.fileName}: #{error.problem} (Line: #{error.lineNumber}, Column: #{error.columnNumber})"
            else 
              lineColumnRegEx = /line\s(\d+)\scolumn\s(\d+)/
              match = lineColumnRegEx.exec(error.problem)
              if match? and match.length > 2
                error.lineNumber = match[1]
                error.columnNumber = match[2]
              errorMessage = "#{error.fileName}: #{error.problem}"
            message += '<br/>' + errorMessage

            atom.project.errors[error.filePath] ?= []
            atom.project.errors[error.filePath].push(error)
        else
          message = 'Compile Project Failed To Compile'
          message += '<br/>' + @result.body
          @obj.stackTrace = @result.stack_trace
          @obj.isException = @result.stack_trace?

        @obj.message = message
        @obj.indicator = 'danger'
    return @obj

class RunTestsParser extends CommandParser

  commandAliases: ['test_async']

  parse: ->
    @obj.indicator = 'warning'
    passCounter = 0
    failedCounter = 0

    for apexClass in @result
      for test in apexClass.detailed_results
        if test.Outcome == "Fail"
          failedCounter++
          @obj.message = "#{failedCounter} failed test method"
          @obj.message += 's' if failedCounter > 1
          @obj.stackTrace += "#{test.ApexClass.Name}.#{test.MethodName}:\n#{test.StackTrace}\n\n"
        else
          passCounter++


    if failedCounter == 0
      @obj.message = "Run all tests complete. #{passCounter} test" + (if passCounter > 1 then "s " else " ") + "passed."
      @obj.indicator = 'success'
    else
      @obj.indicator = 'danger'
      @obj.isException = true

    return @obj

class StartLoggingParser extends CommandParser

  parse: ->
    @obj.indicator = 'warning'

    if @result.success is false
      @obj.indicator = 'danger'
      @obj.isException = true
      @obj.stackTrace = @result.stack_trace
    else
      @obj.indicator = 'success'

    @obj.message = @result.body
    return @obj

parsers = { 
  CommandParser: CommandParser,
  DeleteParser: DeleteParser,
  UiParser: UiParser,
  CompileParser: CompileParser,
  CompileProjectParser: CompileProjectParser,
  RunTestsParser: RunTestsParser,
  StartLoggingParser: StartLoggingParser,
  GetOrgWideTestCoverageParser: GetOrgWideTestCoverageParser
}

getCommandParser = (command, params) ->
  
  if params.args? and params.args.ui
    return UiParser
  else
    parserClassName = _.camelize(command)
    parserClassName = _.capitalize(parserClassName)
    parserClassName += 'Parser'
    console.log parserClassName
    if parserClassName not of parsers
      return CommandParser
    else
      return parsers[parserClassName]

module.exports =
  
  parse: (command, params, result) ->
    Parser = getCommandParser(command, params)
    console.log 'parser is: '
    console.log Parser
    parser = new Parser(command, params, result)
    return parser.parse()
































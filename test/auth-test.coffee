# Notes:
#  Copyright 2016 Hewlett-Packard Development Company, L.P.
#
#  Permission is hereby granted, free of charge, to any person obtaining a
#  copy of this software and associated documentation files (the "Software"),
#  to deal in the Software without restriction, including without limitation
#  the rights to use, copy, modify, merge, publish, distribute, sublicense,
#  and/or sell copie of the Software, and to permit persons to whom the
#  Software is furnished to do so, subject to the following conditions:
#
#  The above copyright notice and this permission notice shall be included in
#  all copies or substantial portions of the Software.
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#  SOFTWARE.

# change log level to eliminate hubot warning about copoyright style

Helper = require 'hubot-test-helper'
chai = require 'chai'
nock = require 'nock'
auth_lib = require '../lib/authentication.coffee'
auth_service = require('he-auth-service')
commons = new (require('../lib/commons.coffee'))()

expect = chai.expect

process.env[auth_lib.env.ENABLE] = 1
auth_service_endpoint = 'https://localhost/'
process.env[auth_lib.env.ENDPOINT] = auth_service_endpoint
helper = new Helper(['../src/0_bootstrap.coffee'])

describe 'Authentication', ->
  metadata =
    short_desc: 'Blah Blah'
    long_desc: 'Blah blah blah blah blah blah blah'
    name: 'mock-auth-integration'

  beforeEach ->
    @room = helper.createRoom()

  afterEach ->
    @room.destroy()
    nock.cleanAll()

  # TODO: test when environment variables are not correctly set

  it 'should specify authentication method via integration registration', ->
    # Empty object params are allowed in basic_auth
    basic_auth = @room.robot.e.auth.generate_basic_auth({})
    expect(basic_auth).have.keys(['type', 'params'])

    params =
      endpoint:
        url: "http://mybasicauthserver.example.com"
        verb: "GET"

    basic_auth = @room.robot.e.auth.generate_basic_auth(params)
    expect(basic_auth).have.keys(['type', 'params'])
    expect(basic_auth.params.endpoint).to.exist.and.to.be.an('object')
    expect(basic_auth.params.endpoint.url).to.exist.and.to.be.a('string')
    expect(basic_auth.params.endpoint.verb).to.exist.and.to.be.a('string')
    @room.robot.e.registerIntegration(metadata, basic_auth)

  it 'should fail registration when using unsupported authentication' +
      ' method', (done) ->
    method = {
      type: 'unsupported'
    }
    try
      @room.robot.e.registerIntegration(metadata, method)
    catch e
      expect(e).to.exist
      expect(e.toString()).to.equal(
        @room.robot.e.auth.errors.unsupported_type.toString())
      return done()
    done(new Error('did not throw expected exception'))


  it 'should fail registration when not specifying type in the ' +
      'authentication method', (done) ->
    method = {
    }
    try
      @room.robot.e.registerIntegration(metadata, method)
    catch e
      expect(e).to.exist
      expect(e.toString()).to.equal(
        @room.robot.e.auth.errors.no_type.toString())
      return done()
    done(new Error('did not throw expected exception'))

  it 'should load integration without authentication', ->
    # If it doesn't blow up with an exception, everything went well :)
    @room.robot.e.registerIntegration(metadata, null)

  describe 'Test Auth Flows and Service Integrations', ->
    metadata =
      short_desc: 'Basic Auth Example'
      long_desc: 'Showcases how to write an integration ' +
        'that uses BasicAuthentication'
      name: "basic_auth"

    command_params =
      verb: 'get'
      entity: 'something'
      type: 'respond'

    integration_name = 'basic_auth'

    command =
      integration_name + ' ' +
        command_params.verb + ' ' +
        command_params.entity

    user_id = 'pedro'

    should_fail_message = 'Should not run this command, it should fail ' +
      'before internally'

    command_should_not_run = (msg) ->
      msg.reply should_fail_message


    TEST_TIMEOUT = 10000
    ASYNC_MESSAGE_TIMEOUT = 2000

    beforeEach ->
      # register module
      params =
        endpoint:
          url: "http://mybasicauthserver.example.com"
          verb: "GET"

      basic_auth = @room.robot.e.auth.generate_basic_auth(params)
      @room.robot.e.registerIntegration(metadata, basic_auth)

    it 'should perform integration command when secrets exist', (done) ->
      this.timeout(TEST_TIMEOUT)
      secrets_payload =
        secrets:
          token: 'cmljYXJkbzpteXBhc3M='
        user_info:
          id: user_id
        integration_info:
          name: integration_name

      path = '/secrets/' +
        user_id + '/' +
        integration_name

      nock(auth_service_endpoint)
      .get(path)
      .reply(200, secrets_payload)

      success_reply = 'You successfully executed command for integration ' +
        integration_name

      authenticated_command = (msg, auth) ->
        try
          expect(msg).to.exist
          expect(auth).to.exist
          expect(auth.secrets).to.exist
          expect(auth.user_info).to.exist
          expect(auth.integration_info).to.exist
          expect(auth.secrets.token).to.exist
          expect(auth.user_info.id).to.exist
          expect(auth.integration_info.name).to.exist
          msg.reply success_reply
        catch e
          msg.reply e.toString()

      # Authentication is enabled be default for this command
      @room.robot.e.create(command_params, authenticated_command)
      msg_interaction = [
        [user_id, '@hubot basic_auth get something'],
        ['hubot', '@' + user_id + ' ' + success_reply]
      ]
      messages = @room.messages
      @room.user.say(msg_interaction[0][0], msg_interaction[0][1]).then ->
        setTimeout(() ->
          expect(messages).to.eql msg_interaction
          done()
        ASYNC_MESSAGE_TIMEOUT)
      .catch (e) ->
        done(e)

    it 'should send error message to user if endpoint of auth ' +
        'service is not available', (done) ->
      this.timeout(TEST_TIMEOUT)

      # Authentication is enabled be default for this command
      @room.robot.e.create(command_params, command_should_not_run)

      path = '/secrets/' +
        user_id + '/' +
        integration_name

      e1 = new Error('connect ECONNREFUSED 127.0.0.1:443')

      nock(auth_service_endpoint)
      .get(path)
      .replyWithError(e1)

      expectedError = commons.authentication_error_message(e1)

      conversation = [
        ['pedro', '@hubot basic_auth get something'],
        ['hubot', '@pedro ' + expectedError]
      ]

      messages = @room.messages
      @room.user.say(conversation[0][0], conversation[0][1])
      .then ->
        setTimeout(() ->
          expect(messages).to.eql(conversation)
          done()
        ASYNC_MESSAGE_TIMEOUT)
      .catch (e) ->
        done(e)

    it 'should send error message to user if auth service responds ' +
        'errors other than 404', (done) ->
      this.timeout(TEST_TIMEOUT)

      path = '/secrets/' +
        user_id + '/' +
        integration_name

      response =
        message: 'There was an internal server error while ' +
          'retrieving secrets at ' + path

      nock(auth_service_endpoint)
      .get(path)
      .reply(500, response)

      # Authentication is enabled be default for this command
      @room.robot.e.create(command_params, command_should_not_run)

      expectedError = commons.authentication_error_message(
        new Error(auth_service.client.UNEXPECTED_STATUS_CODE + '500'))

      conversation = [
        ['pedro', '@hubot basic_auth get something'],
        ['hubot', '@pedro ' + expectedError]
      ]
      messages = @room.messages
      @room.user.say(conversation[0][0], conversation[0][1])
      .then ->
        setTimeout(() ->
          expect(messages).to.eql(conversation)
          done()
        ASYNC_MESSAGE_TIMEOUT)
      .catch (e) ->
        done(e)

    it 'should send error to user when auth service fail to ' +
        'generate token_url', (done) ->
      this.timeout(TEST_TIMEOUT)

      path = '/secrets/' +
        user_id + '/' +
        integration_name

      response =
        message: 'Error retrieving secrets at ' + path

      token_response =
        message: 'High volume of requests, server unavailable.' +
          ' Please try again later.'

      nock(auth_service_endpoint)
      .get(path)
      .reply(404, response)

      nock(auth_service_endpoint)
      .post('/token_urls')
      .reply(500, token_response)

      # Authentication is enabled be default for this command
      @room.robot.e.create(command_params, command_should_not_run)

      expectedError = commons.authentication_error_message(
        new Error(auth_service.client.UNEXPECTED_STATUS_CODE + '500'))

      conversation = [
        ['pedro', '@hubot basic_auth get something'],
        ['hubot', '@pedro ' + commons.authentication_announcement(command)],
        ['hubot', '@pedro ' + expectedError]
      ]

      messages = @room.messages
      @room.user.say(conversation[0][0], conversation[0][1])
      .then ->
        setTimeout(() ->
          expect(messages).to.eql(conversation)
          done()
        ASYNC_MESSAGE_TIMEOUT)
      .catch (e) ->
        done(e)

    it 'should send error to user when auth service is not available to' +
        'generate token_url', (done) ->
      this.timeout(TEST_TIMEOUT)

      path = '/secrets/' +
        user_id + '/' +
        integration_name

      response =
        message: 'Error retrieving secrets at ' + path

      nock(auth_service_endpoint)
      .get(path)
      .reply(404, response)

      e1 = new Error('connect ECONNREFUSED 127.0.0.1:443')

      nock(auth_service_endpoint)
      .post('/token_urls')
      .replyWithError(e1)

      # Authentication is enabled be default for this command
      @room.robot.e.create(command_params, command_should_not_run)

      expectedError = commons.authentication_error_message(e1)

      conversation = [
        ['pedro', '@hubot basic_auth get something'],
        ['hubot', '@pedro ' + commons.authentication_announcement(command)]
        ['hubot', '@pedro ' + expectedError]
      ]

      messages = @room.messages
      @room.user.say(conversation[0][0], conversation[0][1])
      .then ->
        setTimeout(() ->
          expect(messages).to.eql(conversation)
          done()
        ASYNC_MESSAGE_TIMEOUT)
      .catch (e) ->
        done(e)

    it 'should send user a token_url if secrets not found ' +
        '(not authenticated)', (done) ->
      this.timeout(TEST_TIMEOUT)

      path = '/secrets/' +
        user_id + '/' +
        integration_name

      response =
        message: 'Error retrieving secrets at ' + path

      portal_endpoint = 'https://he-portal.hpe.com'
      portal_path = '/portal'
      token = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.' +
        'eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiYWRtaW4iO' +
        'nRydWV9.TJVA95OrM7E2cBab30RMHrHDcEfxjoYZgeFONFh7HgQ'
      token_response =
        message: 'token_url created'
        token: token
        url: portal_endpoint + portal_path + '/' + token

      nock(auth_service_endpoint)
      .get(path)
      .reply(404, response)

      nock(auth_service_endpoint)
      .post('/token_urls')
      .reply(201, token_response)

      # Authentication is enabled be default for this command
      @room.robot.e.create(command_params, command_should_not_run)

      expectedMsg = commons.authentication_message(command, token_response.url)

      conversation = [
        ['pedro', '@hubot basic_auth get something'],
        ['hubot', '@pedro ' + commons.authentication_announcement(command)],
        ['hubot', '@pedro ' + expectedMsg]
      ]

      messages = @room.messages
      @room.user.say(conversation[0][0], conversation[0][1])
      .then ->
        setTimeout(() ->
          expect(messages).to.eql(conversation)
          done()
        ASYNC_MESSAGE_TIMEOUT)
      .catch (e) ->
        done(e)

  describe 'Test BasicAuth', ->
    metadata =
      short_desc: 'Basic Auth Example'
      long_desc: 'Showcases how to write an integration ' +
        'that uses BasicAuthentication'
      name: "basic_auth"

    command_params =
      verb: 'get'
      entity: 'something'
      type: 'respond'

    integration_name = 'basic_auth'

    it 'Should fail if basic auth config has invalid endpoint configs', (done) ->
      this.timeout(5000)
      # Endpoint is null
      basic_auth =
        type: auth_lib.TYPES.BASIC_AUTH
        params:
          endpoint: null
      try
        @room.robot.e.registerIntegration(metadata, basic_auth)
        return done(new Error('Should have failed with null endpoint'))
      catch e
        expect(e).to.exist
        expect(e.toString())
          .to
          .equal(auth_lib.errors.failed_validation.toString())

      # Change it to a string
      basic_auth.params.endpoint = ""
      try
        @room.robot.e.registerIntegration(metadata, basic_auth)
        return done(new Error('Should have failed with endpoint with string value'))
      catch e
        expect(e).to.exist
        expect(e.toString())
          .to
          .equal(auth_lib.errors.failed_validation.toString())

      # Change it to a string
      basic_auth.params.endpoint = 0
      try
        @room.robot.e.registerIntegration(metadata, basic_auth)
        return done(new Error('Should have failed with endpoint with numeric value'))
      catch e
        expect(e).to.exist
        expect(e.toString())
          .to
          .equal(auth_lib.errors.failed_validation.toString())

      # Change it to an empty object
      basic_auth.params.endpoint = {}
      try
        @room.robot.e.registerIntegration(metadata, basic_auth)
        return done(new Error('Should have failed with endpoint with an empty object value'))
      catch e
        expect(e).to.exist
        expect(e.toString())
          .to
          .equal(auth_lib.errors.failed_validation.toString())

      # Endpoint with null url
      basic_auth.params.endpoint =
        url: null
        verb: "SOMETHING"
      try
        @room.robot.e.registerIntegration(metadata, basic_auth)
        return done(new Error('Should have failed with endpoint with null url'))
      catch e
        expect(e).to.exist
        expect(e.toString())
          .to
          .equal(auth_lib.errors.failed_validation.toString())

      # Endpoint with no verb
      basic_auth.params.endpoint =
        url: "http://basic_auth_server.example.com"
      try
        @room.robot.e.registerIntegration(metadata, basic_auth)
        return done(new Error('Should have failed with non-existing endpoint verb'))
      catch e
        expect(e).to.exist
        expect(e.toString())
          .to
          .equal(auth_lib.errors.failed_validation.toString())

      # Endpoint with null verb
      basic_auth.params.endpoint =
        url: "http://basic_auth_server.example.com"
        verb: null
      try
        @room.robot.e.registerIntegration(metadata, basic_auth)
        return done(new Error('Should have failed with non-existing endpoint verb'))
      catch e
        expect(e).to.exist
        expect(e.toString())
          .to
          .equal(auth_lib.errors.failed_validation.toString())

      # Endpoint with verb with strange value
      basic_auth.params.endpoint =
        url: "http://basic_auth_server.example.com"
        verb: 9
      try
        @room.robot.e.registerIntegration(metadata, basic_auth)
        return done(new Error('Should have failed with unsupported value endpoint verb'))
      catch e
        expect(e).to.exist
        expect(e.toString())
          .to
          .equal(auth_lib.errors.failed_validation.toString())

      # Endpoint with unsupported verb
      basic_auth.params.endpoint =
        url: "http://basic_auth_server.example.com"
        verb: "SOMETHING"
      try
        @room.robot.e.registerIntegration(metadata, basic_auth)
        return done(new Error('Should have failed with unsupported endpoint verb'))
      catch e
        expect(e).to.exist
        expect(e.toString())
          .to
          .equal(auth_lib.errors.failed_validation.toString())

      # Endpoint with valid verb but not well formed
      basic_auth.params.endpoint =
        url: "http://basic_auth_server.example.com"
        verb: "Get"
      try
        @room.robot.e.registerIntegration(metadata, basic_auth)
        return done(new Error('Should have failed with unsupported endpoint verb'))
      catch e
        expect(e).to.exist
        expect(e.toString())
          .to
          .equal(auth_lib.errors.failed_validation.toString())

      done()

      basic_auth = @room.robot.e.auth.generate_basic_auth({})
      @room.robot.e.registerIntegration(metadata, basic_auth)

    it 'Should be successful if registered with valid basic auth info', (done) ->
      basic_auth =
        type: auth_lib.TYPES.BASIC_AUTH
        params:
          url: "http://mybasicauth.example.com"
          verb: "GET"
      try
        @room.robot.e.registerIntegration(metadata, basic_auth)
        done()
      catch e
        done(e)

    it 'Should be successful if registered with valid info generated with helper', (done) ->
      params =
          url: "http://mybasicauth.example.com"
          verb: "GET"
      try
        basic_auth = @room.robot.e.auth.generate_basic_auth(params)
        @room.robot.e.registerIntegration(metadata, basic_auth)
        done()
      catch e
        done(e)

    it 'Should be successful if registered with parametrized helper method', (done) ->

      url = "http://mybasicauth.example.com"
      verb = "GET"
      try
        basic_auth = @room.robot.e.auth.create_basic_auth_config(url, verb)
        # TODO: verify basic_auth object
        expect(basic_auth.ttl).to.equal(auth_lib.values.DEFAULT_SECRETS_TTL)
        @room.robot.e.registerIntegration(metadata, basic_auth)
        done()
      catch e
        done(e)

    it 'Should be successful if registered with parametrized helper method + custom ttl', (done) ->

      url = "http://mybasicauth.example.com"
      verb = "GET"
      custom_ttl = 900
      try
        basic_auth = @room.robot.e.auth.create_basic_auth_config(url, verb, custom_ttl)
        # TODO: verify basic_auth object
        expect(basic_auth.ttl).to.equal(custom_ttl)
        @room.robot.e.registerIntegration(metadata, basic_auth)
        done()
      catch e
        done(e)

  describe 'Test IdM Auth', ->
    reg =
      short_desc: 'IdM Auth Example'
      long_desc: 'Showcases how to write an integration ' +
        'that uses IdmAuth'
      name: "idm_auth"

    it 'Should be successful if registered with valid idm auth info', (done) ->
      idm_auth =
        type: auth_lib.TYPES.IDM_AUTH
        params:
          endpoint:
            verb: "POST"
            url: "http://myidmservice.example.com"
      try
        @room.robot.e.registerIntegration(metadata, idm_auth)
        done()
      catch e
        done(e)

    it 'Should be successful if registered with valid idm info generated with helper', (done) ->
      params =
        endpoint:
          verb: "POST"
          url: "http://myidmservice.example.com"
      try
        idm_auth = @room.robot.e.auth.generate_idm_auth(params)
        @room.robot.e.registerIntegration(metadata, idm_auth)
        done()
      catch e
        done(e)

    it 'Should be successful if registered with parametrized helper method', (done) ->
      url = "http://myidmservice.example.com"
      verb = "POST"
      try
        idm_auth = @room.robot.e.auth.create_idm_auth_config(url)
        expect(idm_auth).to.exist
        expect(idm_auth).to.have.keys(["type", "params", "ttl"])
        expect(idm_auth.type).to.equal(auth_lib.TYPES.IDM_AUTH)
        expect(idm_auth.params).to.be.an('object')
        expect(idm_auth.params.endpoint).to.exist.and.have.keys(["url", "verb"])
        expect(idm_auth.params.endpoint.verb).to.equal(verb)
        expect(idm_auth.params.endpoint.url).to.equal(url)
        expect(idm_auth.ttl).to.equal(auth_lib.values.DEFAULT_SECRETS_TTL)
        @room.robot.e.registerIntegration(metadata, idm_auth)
        done()
      catch e
        done(e)

    it 'Should be successful if registered with customized ttl', (done) ->
      url = "http://myidmservice.example.com"
      verb = "POST"
      try
        idm_auth = @room.robot.e.auth.create_idm_auth_config(url)
        expect(idm_auth).to.exist
        expect(idm_auth).to.have.keys(["type", "params", "ttl"])
        expect(idm_auth.type).to.equal(auth_lib.TYPES.IDM_AUTH)
        expect(idm_auth.params).to.be.an('object')
        expect(idm_auth.params.endpoint).to.exist.and.have.keys(["url", "verb"])
        expect(idm_auth.params.endpoint.verb).to.equal(verb)
        expect(idm_auth.params.endpoint.url).to.equal(url)
        expect(idm_auth.ttl).to.equal(auth_lib.values.DEFAULT_SECRETS_TTL)
        @room.robot.e.registerIntegration(metadata, idm_auth)
        done()
      catch e
        done(e)

    it 'Should fail if parametrized helper method has invalid inputs for url', (done) ->
      url = ""
      try
        @room.robot.e.auth.create_idm_auth_config(url)
        return done(new Error('Should have failed with empty url'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal('Error: Auth endpoint configuration is missing url:' +
            ' {\n  "url": "",\n  "verb": "POST"\n}')

      url = undefined
      try
        @room.robot.e.auth.create_idm_auth_config(url)
        return done(new Error('Should have failed with undef url'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal('Error: Auth endpoint configuration is missing url:' +
            ' {\n  "verb": "POST"\n}')

      url = null
      try
        @room.robot.e.auth.create_idm_auth_config(url)
        return done(new Error('Should have failed with null url'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal('Error: Auth endpoint configuration is missing url:' +
            ' {\n  "url": null,\n  "verb": "POST"\n}')

      url = {}
      try
        @room.robot.e.auth.create_idm_auth_config(url)
        return done(new Error('Should have failed with wrong type url'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal('Error: Auth endpoint url is empty: ' +
            '{\n  "url": {},\n  "verb": "POST"\n}')

      done()

    it 'Should be successful if registered with parametrized helper method with tenant info', (done) ->
      url = "http://myidmservice.example.com"
      verb = "POST"
      tenant_username = "tenantUser1"
      tenant_password = "verySecureTenantPassword"
      tenant_name = "group1"
      try
        idm_auth = @room.robot.e.auth.create_idm_auth_config(
          url, tenant_username, tenant_password, tenant_name)
        expect(idm_auth).to.exist
        expect(idm_auth).to.have.keys(["type", "params", "ttl"])
        expect(idm_auth.type).to.equal(auth_lib.TYPES.IDM_AUTH)
        expect(idm_auth.ttl).to.equal(auth_lib.values.DEFAULT_SECRETS_TTL)
        expect(idm_auth.params).to.be.an('object')
        expect(idm_auth.params).to.have.keys(["endpoint", "tenant"])
        expect(idm_auth.params.endpoint).to.have.keys(["url", "verb"])
        expect(idm_auth.params.endpoint.verb).to.equal(verb)
        expect(idm_auth.params.endpoint.url).to.equal(url)
        expect(idm_auth.params.tenant.username).to.equal(tenant_username)
        expect(idm_auth.params.tenant.password).to.equal(tenant_password)
        expect(idm_auth.params.tenant.name).to.equal(tenant_name)
        @room.robot.e.registerIntegration(metadata, idm_auth)
        done()
      catch e
        done(e)

    it 'Should be successful if registered with tenant info and custom ttl', (done) ->
      url = "http://myidmservice.example.com"
      verb = "POST"
      tenant_username = "tenantUser1"
      tenant_password = "verySecureTenantPassword"
      tenant_name = "group1"
      custom_ttl = 900
      try
        idm_auth = @room.robot.e.auth.create_idm_auth_config(
          url, tenant_username, tenant_password, tenant_name, custom_ttl)
        expect(idm_auth).to.exist
        expect(idm_auth).to.have.keys(["type", "params", "ttl"])
        expect(idm_auth.type).to.equal(auth_lib.TYPES.IDM_AUTH)
        expect(idm_auth.ttl).to.equal(custom_ttl)
        expect(idm_auth.params).to.be.an('object')
        expect(idm_auth.params).to.have.keys(["endpoint", "tenant"])
        expect(idm_auth.params.endpoint).to.have.keys(["url", "verb"])
        expect(idm_auth.params.endpoint.verb).to.equal(verb)
        expect(idm_auth.params.endpoint.url).to.equal(url)
        expect(idm_auth.params.tenant.username).to.equal(tenant_username)
        expect(idm_auth.params.tenant.password).to.equal(tenant_password)
        expect(idm_auth.params.tenant.name).to.equal(tenant_name)
        @room.robot.e.registerIntegration(metadata, idm_auth)
        done()
      catch e
        done(e)

    it 'Should be successful if registered with parametrized helper method with empty tenant info', (done) ->
      url = "http://myidmservice.example.com"
      verb = "POST"
      tenant_username = ""
      tenant_password = ""
      tenant_name = ""
      try
        idm_auth = @room.robot.e.auth.create_idm_auth_config(
          url, tenant_username, tenant_password, tenant_name)
        expect(idm_auth).to.exist
        expect(idm_auth).to.have.keys(["type", "params", "ttl"])
        expect(idm_auth.type).to.equal(auth_lib.TYPES.IDM_AUTH)
        expect(idm_auth.params).to.be.an('object')
        expect(idm_auth.params).to.have.keys(["endpoint"])
        expect(idm_auth.params.endpoint).to.have.keys(["url", "verb"])
        expect(idm_auth.params.endpoint.verb).to.equal(verb)
        expect(idm_auth.params.endpoint.url).to.equal(url)
        expect(idm_auth.params.tenant).not.to.exist
      catch e
        return done(e)

      tenant_username = null
      tenant_password = undefined
      tenant_name = null
      try
        idm_auth = @room.robot.e.auth.create_idm_auth_config(
          url, tenant_username, tenant_password, tenant_name)
        expect(idm_auth).to.exist
        expect(idm_auth).to.have.keys(["type", "params", "ttl"])
        expect(idm_auth.type).to.equal(auth_lib.TYPES.IDM_AUTH)
        expect(idm_auth.params).to.be.an('object')
        expect(idm_auth.params).to.have.keys(["endpoint"])
        expect(idm_auth.params.endpoint).to.have.keys(["url", "verb"])
        expect(idm_auth.params.endpoint.verb).to.equal(verb)
        expect(idm_auth.params.endpoint.url).to.equal(url)
        expect(idm_auth.params.tenant).not.to.exist
      catch e
        return done(e)

      try
        # TODO: revise if omitting tenant params is a best practice.
        idm_auth = @room.robot.e.auth.create_idm_auth_config(url)
        expect(idm_auth).to.exist
        expect(idm_auth).to.have.keys(["type", "params", "ttl"])
        expect(idm_auth.type).to.equal(auth_lib.TYPES.IDM_AUTH)
        expect(idm_auth.params).to.be.an('object')
        expect(idm_auth.params).to.have.keys(["endpoint"])
        expect(idm_auth.params.endpoint).to.have.keys(["url", "verb"])
        expect(idm_auth.params.endpoint.verb).to.equal(verb)
        expect(idm_auth.params.endpoint.url).to.equal(url)
        expect(idm_auth.params.tenant).not.to.exist
      catch e
        return done(e)

      done()

    it 'Should fail if parametrized helper method has invalid inputs for tenant', (done) ->
      url = "http://myidmservice.example.com"
      try
        @room.robot.e.auth.create_idm_auth_config(url, {}, "something", "Mr.T")
        return done(new Error('Should have failed differently'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal('Error: Tenant username is not valid = {}')

      try
        @room.robot.e.auth.create_idm_auth_config(url, "something", 9, "Mr.T")
        return done(new Error('Should have failed differently'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal('Error: Tenant password is not valid = 9')

      try
        @room.robot.e.auth.create_idm_auth_config(url, "myusername", "", "Mr.T")
        return done(new Error('Should have failed differently'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal('Error: Tenant password is not valid = ""')

      try
        @room.robot.e.auth.create_idm_auth_config(url, "", "mypassword", "Mr.T")
        return done(new Error('Should have failed differently'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal('Error: Tenant username is not valid = ""')

      try
        @room.robot.e.auth.create_idm_auth_config(url, "u", "p", "")
        return done(new Error('Should have failed differently'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal('Error: Tenant name is not valid = ""')

      done()

    it 'Should fail if idm auth config has invalid endpoint configs', (done) ->
      this.timeout(5000)
      # Params are undef
      idm_auth =
        type: auth_lib.TYPES.IDM_AUTH

      try
        @room.robot.e.registerIntegration(reg, idm_auth)
        return done(new Error('Should have failed with undefined params'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal(auth_lib.errors.failed_validation.toString())

      # Endpoint params are empty
      idm_auth =
        type: auth_lib.TYPES.IDM_AUTH
        params: {}
      try
        @room.robot.e.registerIntegration(reg, idm_auth)
        return done(new Error('Should have failed with empty params'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal(auth_lib.errors.failed_validation.toString())

      # Endpoint params empty endpoint
      idm_auth =
        type: auth_lib.TYPES.IDM_AUTH
        params:
          endpoint: {}

      try
        @room.robot.e.registerIntegration(reg, idm_auth)
        return done(new Error('Should have failed with empty endpoint'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal(auth_lib.errors.failed_validation.toString())

      # Endpoint params missing verb
      idm_auth =
        type: auth_lib.TYPES.IDM_AUTH
        params:
          endpoint:
            url: "http://myidmservice.example.com"
      try
        @room.robot.e.registerIntegration(reg, idm_auth)
        return done(new Error('Should have failed with missing verb'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal(auth_lib.errors.failed_validation.toString())

      # Endpoint params missing url
      idm_auth =
        type: auth_lib.TYPES.IDM_AUTH
        params:
          endpoint:
            verb: "POST"
      try
        @room.robot.e.registerIntegration(reg, idm_auth)
        return done(new Error('Should have failed with missing url'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal(auth_lib.errors.failed_validation.toString())

      # Endpoint params empty url
      idm_auth =
        type: auth_lib.TYPES.IDM_AUTH
        params:
          endpoint:
            url: ""
            verb: "POST"
      try
        @room.robot.e.registerIntegration(reg, idm_auth)
        return done(new Error('Should have failed with empty url'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal(auth_lib.errors.failed_validation.toString())

      # Endpoint params with invalid url
      idm_auth =
        type: auth_lib.TYPES.IDM_AUTH
        params:
          endpoint:
            url: {}
            verb: "POST"

      # Endpoint params null url
      idm_auth =
        type: auth_lib.TYPES.IDM_AUTH
        params:
          endpoint:
            url: null
            verb: "POST"
      try
        @room.robot.e.registerIntegration(reg, idm_auth)
        return done(new Error('Should have failed with null url'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal(auth_lib.errors.failed_validation.toString())

      # Endpoint params with invalid url
      idm_auth =
        type: auth_lib.TYPES.IDM_AUTH
        params:
          endpoint:
            url: {}
            verb: "POST"
      try
        @room.robot.e.registerIntegration(reg, idm_auth)
        return done(new Error('Should have failed with invalid type url'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal(auth_lib.errors.failed_validation.toString())

      # Endpoint params with unsupported verb
      idm_auth =
        type: auth_lib.TYPES.IDM_AUTH
        params:
          endpoint:
            url: {}
            verb: "SOMETHING_ELSE"
      try
        @room.robot.e.registerIntegration(reg, idm_auth)
        return done(new Error('Should have failed with unsupported verb'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal(auth_lib.errors.failed_validation.toString())

      done()

    it 'Should create auth object for idm auth using convenience method.', (done) ->
      params =
        endpoint:
          verb: "POST"
          url: "http://myidmservice.example.com"
      try
        idm_auth = @room.robot.e.auth.generate_idm_auth(params)
        expect(idm_auth).to.exist
        expect(idm_auth).to.have.keys(['type', 'params'])
        expect(idm_auth.type).to.equal(auth_lib.TYPES.IDM_AUTH)
        expect(idm_auth.params.endpoint).to.exist.and.be.an('object')
        expect(idm_auth.params.endpoint).to.have.keys(['verb', 'url'])
        expect(idm_auth.params.endpoint.verb).to.be.a('string').and.equal('POST')
        expect(idm_auth.params.endpoint.url).to.exist.and.be.a('string')
        done()
      catch e
        done(e)

    it 'Should fail if params to convenience method has invalid values.', (done) ->
      this.timeout(5000)
      # Params are undef
      try
        @room.robot.e.auth.generate_idm_auth null
        return done(new Error('Should have failed with undefined params'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal('Error: Missing required params object or invalid type: null')

      # Endpoint params are empty
      try
        @room.robot.e.auth.generate_idm_auth {}
        return done(new Error('Should have failed with empty params'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal('Error: Missing required endpoint or invalid type: undefined')

      # Endpoint params empty endpoint
      params =
        endpoint: {}
      try
        @room.robot.e.auth.generate_idm_auth params
        return done(new Error('Should have failed with empty endpoint'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal('Error: Auth endpoint configuration is missing url: {}')

      # Endpoint params missing verb
      params =
        endpoint:
          url: "http://myidmservice.example.com"
      try
        @room.robot.e.auth.generate_idm_auth params
        return done(new Error('Should have failed with missing verb'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal('Error: Auth endpoint configuration is missing verb:' +
            ' {\n  "url": "http://myidmservice.example.com"\n}')

      # Endpoint params missing url
      idm_auth =
        type: auth_lib.TYPES.IDM_AUTH
      params =
        endpoint:
          verb: "POST"
      try
        @room.robot.e.auth.generate_idm_auth params
        return done(new Error('Should have failed with missing url'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal('Error: Auth endpoint configuration is missing url:' +
            ' {\n  "verb": "POST"\n}')

      # Endpoint params empty url
      params =
        endpoint:
          url: ""
          verb: "POST"
      try
        @room.robot.e.auth.generate_idm_auth params
        return done(new Error('Should have failed with empty url'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal('Error: Auth endpoint configuration is missing url:' +
            ' {\n  "url": "",\n  "verb": "POST"\n}')

      # Endpoint params with invalid url
      idm_auth =
        type: auth_lib.TYPES.IDM_AUTH
        params:
          endpoint:
            url: {}
            verb: "POST"

      # Endpoint params null url
      params =
        endpoint:
          url: null
          verb: "POST"
      try
        @room.robot.e.auth.generate_idm_auth params
        return done(new Error('Should have failed with null url'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal('Error: Auth endpoint configuration is missing url:' +
            ' {\n  "url": null,\n  "verb": "POST"\n}')

      # Endpoint params with invalid url
      params =
        endpoint:
          url: {}
          verb: "POST"
      try
        @room.robot.e.auth.generate_idm_auth params
        return done(new Error('Should have failed with invalid type url'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal('Error: Auth endpoint url is empty:' +
            ' {\n  "url": {},\n  "verb": "POST"\n}')

      # Endpoint params with unsupported verb
      params =
        endpoint:
          url: "http://myidmauthserver.example.com"
          verb: "SOMETHING_ELSE"
      try
        @room.robot.e.auth.generate_idm_auth params
        return done(new Error('Should have failed with unsupported verb'))
      catch e
        expect(e).to.exist
        expect(e.toString())
        .to
        .equal('Error: Auth endpoint verb is not supported: SOMETHING_ELSE')

      done()

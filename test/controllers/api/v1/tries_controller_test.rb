# frozen_string_literal: true

require 'test_helper'

module Api
  module V1
    class TriesControllerTest < ActionController::TestCase
      let(:joey) { users(:joey) }

      before do
        @controller = Api::V1::TriesController.new

        login_user joey
      end

      def assert_try_matches_response response, try
        assert_equal try.queryParams, response['queryParams']
        assert_equal try.fieldSpec,   response['fieldSpec']
        assert_equal try.searchUrl,   response['searchUrl']
        assert_equal try.tryNo,       response['tryNo']
        assert_equal try.name,        response['name']
        assert_equal try.solr_args,   response['args']
        assert_equal try.escapeQuery, response['escapeQuery']

        assert_curator_vars_equal try.curator_vars_map, response['curatorVars']
      end

      def assert_try_matches_params params, try
        assert_equal try.queryParams, params[:queryParams] if params[:queryParams]
        assert_equal try.fieldSpec,   params[:fieldSpec]   if params[:fieldSpec]
        assert_equal try.searchUrl,   params[:searchUrl]   if params[:searchUrl]
        assert_equal try.name,        params[:name]        if params[:name]
        assert_equal try.escapeQuery, params[:escapeQuery] if params[:escapeQuery]
      end

      def assert_curator_vars_equal vars, response_vars
        if vars.blank?
          assert_equal({}, response_vars)
        else
          vars.each do |key, value|
            assert_equal response_vars[key.to_s], value
          end
        end
      end

      describe 'Fetches case tries' do
        let(:case_with_one_try)   { cases(:case_with_one_try) }
        let(:case_with_two_tries) { cases(:case_with_two_tries) }
        let(:shared_case)         { cases(:shared_team_case) }

        test 'returns a not found error if case does not exist' do
          get :index, case_id: 'foo'

          assert_response :not_found
        end

        test 'returns all tries for a case' do
          get :index, case_id: case_with_one_try.id

          assert_response :ok

          body  = JSON.parse(response.body)
          tries = body['tries']

          assert_equal tries.count, 1

          get :index, case_id: case_with_two_tries.id

          assert_response :ok

          body  = JSON.parse(response.body)
          tries = body['tries']

          assert_equal tries.count, 2
        end

        test 'works for a shared case as well' do
          get :index, case_id: shared_case.id

          first_try = shared_case.tries.first

          assert_response :ok

          body  = JSON.parse(response.body)
          tries = body['tries']

          ids = tries.map { |each| each['tryNo'] }

          assert_includes ids, first_try.tryNo
        end
      end

      describe 'Fetches a specific case try' do
        let(:case_with_one_try)   { cases(:case_with_one_try) }
        let(:case_with_two_tries) { cases(:case_with_two_tries) }

        let(:first_for_case_with_two_tries)   { tries(:first_for_case_with_two_tries) }
        let(:second_for_case_with_two_tries)  { tries(:second_for_case_with_two_tries) }

        test 'returns a not found error when try does not exist' do
          get :show, case_id: case_with_two_tries.id, tryNo: 1234

          assert_response :not_found
        end

        test 'returns a specific case try' do
          get :show, case_id: case_with_two_tries.id, tryNo: first_for_case_with_two_tries.tryNo

          assert_response :ok

          body = JSON.parse(response.body)

          assert_try_matches_response body, first_for_case_with_two_tries

          get :show, case_id: case_with_two_tries.id, tryNo: second_for_case_with_two_tries.tryNo

          assert_response :ok

          body = JSON.parse(response.body)

          assert_try_matches_response body, second_for_case_with_two_tries
        end
      end

      describe 'Updates case tries' do
        let(:the_case)  { cases(:case_with_two_tries) }
        let(:the_try)   { tries(:first_for_case_with_two_tries) }

        test 'renames try successfully' do
          put :update, case_id: the_case.id, tryNo: the_try.tryNo, name: 'New Name'

          assert_response :ok

          the_try.reload
          assert_equal the_try.name, 'New Name'

          the_try = JSON.parse(response.body)
          assert_equal the_try['name'], 'New Name'
        end

        test 'does nothing with params passed except name' do
          old_no = the_try.tryNo
          put :update, case_id: the_case.id, tryNo: the_try.tryNo, queryParams: 'New No'

          assert_response :ok

          the_try.reload
          assert_not_equal  the_try.tryNo, 'New No'
          assert_equal      the_try.tryNo, old_no

          put :update, case_id: the_case.id, tryNo: the_try.tryNo, fieldSpec: 'New fieldSpec'

          assert_response :ok

          the_try.reload
          assert_not_equal the_try.fieldSpec, 'New fieldSpec'
        end
      end

      describe 'Creates new case tries' do
        let(:the_case) { cases(:case_with_one_try) }

        test 'sets attribute successfully and assigns try to case' do
          try_params = {
            searchUrl:    'http://solr.quepid.com',
            fieldSpec:    'catch_line',
            queryParams:  'q=#$query##',
            searchEngine: 'solr',
          }

          case_last_try = the_case.lastTry

          assert_difference 'the_case.tries.count' do
            post :create, try_params.merge(case_id: the_case.id)

            assert_response :ok # should be :created,
            # but there's a bug currently in the responders gem

            the_case.reload
            try_response  = JSON.parse(response.body)
            created_try   = the_case.tries.where(tryNo: try_response['tryNo']).first

            assert_equal the_case.lastTry, case_last_try + 1

            assert_try_matches_response try_response,  created_try
            assert_try_matches_params   try_params,    created_try

            expected_value = { 'q' => [ '#$query##' ] }

            assert expected_value == try_response['args']
          end
        end

        test 'adds curator vars to the try' do
          try_params = {
            searchUrl:    'http://solr.quepid.com',
            fieldSpec:    'catch_line',
            queryParams:  'q=#$query##',
            searchEngine: 'solr',
          }

          curator_vars_params = {
            var1: '1',
            var2: '2',
          }

          try_params[:curatorVars] = curator_vars_params

          assert_difference 'CuratorVariable.count', 2 do
            post :create, try_params.merge(case_id: the_case.id)

            assert_response :ok

            try_response  = json_response
            created_try   = the_case.tries.where(tryNo: try_response['tryNo']).first

            assert_try_matches_response try_response,  created_try
            assert_try_matches_params   try_params,    created_try

            expected_value = { 'q' => [ '#$query##' ] }

            assert expected_value == try_response['args']
          end
        end

        test 'sets default name properly' do
          try_params = {
            searchUrl:    'http://solr.quepid.com',
            fieldSpec:    'catch_line',
            queryParams:  'q=#$query##',
            searchEngine: 'solr',
          }

          post :create, try_params.merge(case_id: the_case.id)

          assert_response :ok # should be :created,
          # but there's a bug currently in the responders gem

          the_case.reload
          try_response  = JSON.parse(response.body)
          created_try   = the_case.tries.where(tryNo: try_response['tryNo']).first

          assert_match( /Try/,                   created_try.name )
          assert_match( /#{the_case.lastTry}/,   created_try.name )
          assert_match( /#{created_try.tryNo}/,  created_try.name )

          assert_match( /Try/,                       try_response['name'] )
          assert_match( /#{the_case.lastTry}/,       try_response['name'] )
          assert_match( /#{try_response['tryNo']}/,  try_response['name'] )
        end

        test 'sets escapeQuery param' do
          try_params = {
            escapeQuery: false,
          }

          post :create, try_params.merge(case_id: the_case.id)

          assert_response :ok

          the_case.reload
          created_try = the_case.tries.where(tryNo: json_response['tryNo']).first

          assert_equal false, json_response['escapeQuery']
          assert_equal false, created_try.escapeQuery
        end

        test 'sets number of rows' do
          try_params = {
            number_of_rows: 20,
          }

          post :create, try_params.merge(case_id: the_case.id)

          assert_response :ok

          the_case.reload
          created_try = the_case.tries.where(tryNo: json_response['tryNo']).first

          assert_equal 20, created_try.number_of_rows
          assert_equal 20, json_response['numberOfRows']
        end

        test 'assigns default attributes' do
          post :create, case_id: the_case.id

          assert_response :ok # should be :created,
          # but there's a bug currently in the responders gem

          the_case.reload
          try_response  = JSON.parse(response.body)
          created_try   = the_case.tries.where(tryNo: try_response['tryNo']).first

          assert_match( /Try/,                   created_try.name )
          assert_match( /#{the_case.lastTry}/,   created_try.name )
          assert_match( /#{created_try.tryNo}/,  created_try.name )

          assert_not_nil created_try.searchEngine
          assert_not_nil created_try.fieldSpec
          assert_not_nil created_try.searchUrl
          assert_not_nil created_try.queryParams
          assert_not_nil created_try.escapeQuery

          assert_equal created_try.searchEngine,    Try::DEFAULTS[:search_engine]
          assert_equal created_try.fieldSpec,       Try::DEFAULTS[:solr][:field_spec]
          assert_equal created_try.searchUrl,       Try::DEFAULTS[:solr][:search_url]
          assert_equal created_try.escapeQuery,     true
          assert_equal created_try.number_of_rows,  10
        end

        describe 'analytics' do
          test 'posts event' do
            expects_any_ga_event_call

            perform_enqueued_jobs do
              post :create, case_id: the_case.id

              assert_response :ok
            end
          end
        end
      end

      describe 'Deletes cases tries' do
        let(:the_case)  { cases(:case_with_two_tries) }
        let(:the_try)   { tries(:first_for_case_with_two_tries) }

        test 'returns a not found error if try does not exist' do
          delete :destroy, case_id: the_case.id, tryNo: 123_456

          assert_response :not_found
        end

        test 'successfully removes try from case tries' do
          assert_difference 'the_case.tries.count', -1 do
            delete :destroy, case_id: the_case.id, tryNo: the_try.tryNo

            assert_response :no_content
          end
        end

        it 'successfully deletes a try with curator vars' do
          the_try.curator_variables.create name: 'foo', value: 1

          assert_difference 'the_case.tries.count', -1 do
            delete :destroy, case_id: the_case.id, tryNo: the_try.tryNo

            assert_response :no_content
          end
        end
      end

      describe 'Supports multiple search engines' do
        let(:the_case)  { cases(:case_with_one_try) }

        describe 'Solr' do
          test 'sets the proper default values' do
            post :create, case_id: the_case.id

            assert_response :ok # should be :created,
            # but there's a bug currently in the responders gem

            the_case.reload
            try_response  = JSON.parse(response.body)
            created_try   = the_case.tries.where(tryNo: try_response['tryNo']).first

            assert_match( /Try/,                   created_try.name )
            assert_match( /#{the_case.lastTry}/,   created_try.name )
            assert_match( /#{created_try.tryNo}/,  created_try.name )

            assert_not_nil created_try.searchEngine
            assert_not_nil created_try.fieldSpec
            assert_not_nil created_try.searchUrl
            assert_not_nil created_try.queryParams
            assert_not_nil created_try.escapeQuery

            assert_equal created_try.searchEngine, Try::DEFAULTS[:search_engine]
            assert_equal created_try.fieldSpec,    Try::DEFAULTS[:solr][:field_spec]
            assert_equal created_try.searchUrl,    Try::DEFAULTS[:solr][:search_url]
            assert_equal created_try.queryParams,  Try::DEFAULTS[:solr][:query_params]
            assert_equal created_try.escapeQuery,  true
          end
        end

        describe 'Elasticsearch' do
          test 'sets the proper default values' do
            post :create, case_id: the_case.id, searchEngine: 'es'

            assert_response :ok # should be :created,
            # but there's a bug currently in the responders gem

            the_case.reload
            try_response  = JSON.parse(response.body)
            created_try   = the_case.tries.where(tryNo: try_response['tryNo']).first

            assert_match( /Try/,                   created_try.name )
            assert_match( /#{the_case.lastTry}/,   created_try.name )
            assert_match( /#{created_try.tryNo}/,  created_try.name )

            assert_not_nil created_try.searchEngine
            assert_not_nil created_try.fieldSpec
            assert_not_nil created_try.searchUrl
            assert_not_nil created_try.queryParams
            assert_not_nil created_try.escapeQuery

            assert_equal created_try.searchEngine, 'es'
            assert_equal created_try.fieldSpec,    Try::DEFAULTS[:es][:field_spec]
            assert_equal created_try.searchUrl,    Try::DEFAULTS[:es][:search_url]
            assert_equal created_try.queryParams,  Try::DEFAULTS[:es][:query_params]
            assert_equal created_try.escapeQuery,  true
          end

          test 'parses args properly' do
            query_params = '{ "query": "#$query##" }'

            post :create, case_id: the_case.id, searchEngine: 'es', queryParams: query_params

            assert_response :ok # should be :created,
            # but there's a bug currently in the responders gem

            the_case.reload
            try_response  = JSON.parse(response.body)
            created_try   = the_case.tries.where(tryNo: try_response['tryNo']).first

            assert_equal created_try.args,      'query' => '#$query##'
            assert_equal try_response['args'],  'query' => '#$query##'
          end

          test 'handles bad JSON in query params' do
            query_params = '{ "query": "#$query##"'

            post :create, case_id: the_case.id, searchEngine: 'es', queryParams: query_params

            assert_response :ok # should be :created,
            # but there's a bug currently in the responders gem

            the_case.reload
            try_response  = JSON.parse(response.body)
            created_try   = the_case.tries.where(tryNo: try_response['tryNo']).first

            assert_nil created_try.args
            assert_nil try_response['args']
          end
        end
      end
    end
  end
end

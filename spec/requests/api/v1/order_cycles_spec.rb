# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "Order cycles", swagger_doc: "v1.yaml" do
  let(:manager) { create(:user, spree_api_key: "order-cycle-api-key") }
  let(:hub) { create(:distributor_enterprise, owner: manager) }
  let(:other_hub) { create(:distributor_enterprise) }
  let!(:order_cycle) do
    create(:simple_order_cycle, coordinator: hub, distributors: [hub, other_hub])
  end
  let!(:unrelated_cycle) do
    create(:simple_order_cycle, coordinator: other_hub, distributors: [other_hub])
  end

  let(:headers) { { "X-Api-Token" => manager.spree_api_key } }
  let(:'X-Api-Token') { manager.spree_api_key }
  let(:response_ids) { json_response[:data].pluck(:id) }

  path "/api/v1/order_cycles" do
    get "List accessible order cycles" do
      tags "Order cycles"
      produces "application/json"
      security [{ api_key_header: [] }, { api_key_param: [] }, { session: [] }]

      description "Returns order cycles visible to the current user, ordered by ID. " \
                  "Includes past, current and future cycles. Distributor IDs follow " \
                  "the existing order-cycle enterprise visibility rules."

      parameter name: "X-Api-Token", in: :header, required: false,
                schema: { type: :string }
      parameter name: :page, in: :query, required: false,
                schema: { type: :integer, minimum: 1, default: 1 }
      parameter name: :per_page, in: :query, required: false,
                schema: { type: :integer, minimum: 1, maximum: 200, default: 50 },
                description: "Rows per page. Values above 200 are capped at 200."

      response "200", "Accessible order cycles, including an empty collection" do
        schema OrderCycleSchema.collection(require_all: true)

        run_test! do
          expect(response_ids).to eq [order_cycle.id.to_s]
          expect(json_response[:data].first[:attributes][:distributor_ids]).
            to match_array [hub.id, other_hub.id]
          expect(json_response.dig(:meta, :pagination)).
            to include(results: 1, page: 1, per_page: 50)
        end
      end

      response "401", "Missing or invalid credentials, or insufficient permission" do
        let(:'X-Api-Token') { "invalid-token" }
        schema ErrorsSchema.schema

        run_test!
      end

      response "422", "Invalid pagination" do
        let(:page) { 0 }
        schema ErrorsSchema.schema

        run_test!
      end
    end
  end

  path "/api/v1/order_cycles/{id}" do
    get "Get an accessible order cycle" do
      tags "Order cycles"
      produces "application/json"
      security [{ api_key_header: [] }, { api_key_param: [] }, { session: [] }]

      parameter name: "X-Api-Token", in: :header, required: false,
                schema: { type: :string }
      parameter name: :id, in: :path, required: true,
                schema: { type: :integer }

      let(:id) { order_cycle.id }

      response "200", "Order cycle details" do
        schema OrderCycleSchema.schema(require_all: true)

        run_test! do
          expect(json_response[:data][:id]).to eq order_cycle.id.to_s
          expect(json_response[:data][:attributes]).to include(
            id: order_cycle.id,
            name: order_cycle.name,
            coordinator_id: hub.id
          )
          expect(json_response[:data][:attributes][:orders_open_at]).
            to eq order_cycle.orders_open_at.as_json
        end
      end

      response "401", "Missing or invalid credentials, or insufficient permission" do
        let(:'X-Api-Token') { "invalid-token" }
        schema ErrorsSchema.schema

        run_test!
      end

      response "404", "Order cycle not found or outside the visible scope" do
        let(:id) { unrelated_cycle.id }
        schema ErrorsSchema.schema

        run_test!
      end
    end
  end

  describe "access control" do
    it "rejects unauthenticated index and show requests" do
      ["/api/v1/order_cycles", "/api/v1/order_cycles/#{order_cycle.id}"].each do |path|
        get path

        expect(response).to have_http_status(:unauthorized)
        expect(json_response[:errors]).to be_present
      end
    end

    it "rejects a user without order-cycle permission" do
      user = create(:user, spree_api_key: "customer-api-key")

      get "/api/v1/order_cycles", headers: { "X-Api-Token" => user.spree_api_key }

      expect(response).to have_http_status(:unauthorized)
    end

    it "allows a participating distributor without exposing the other distributor" do
      login_as other_hub.owner

      get "/api/v1/order_cycles"

      expect(response_ids).to match_array [order_cycle.id.to_s, unrelated_cycle.id.to_s]
      shared_cycle = json_response[:data].find { |record| record[:id] == order_cycle.id.to_s }
      expect(shared_cycle[:attributes][:distributor_ids]).to eq [other_hub.id]

      get "/api/v1/order_cycles/#{order_cycle.id}"

      expect(response).to have_http_status(:ok)
      expect(json_response[:data][:attributes][:distributor_ids]).to eq [other_hub.id]
    end

    it "allows a participating supplier using existing enterprise visibility" do
      supplier = create(:supplier_enterprise)
      create(:exchange, order_cycle:, sender: supplier, receiver: hub, incoming: true)
      login_as supplier.owner

      get "/api/v1/order_cycles"

      expect(response_ids).to eq [order_cycle.id.to_s]

      get "/api/v1/order_cycles/#{order_cycle.id}"

      expect(response).to have_http_status(:ok)
      expect(json_response[:data][:attributes][:distributor_ids]).to eq []
    end

    it "preserves administrator access" do
      login_as create(:admin_user)

      get "/api/v1/order_cycles"

      expect(response_ids).to match_array [order_cycle.id.to_s, unrelated_cycle.id.to_s]

      get "/api/v1/order_cycles/#{order_cycle.id}"

      expect(response).to have_http_status(:ok)
      expect(json_response[:data][:attributes][:distributor_ids]).
        to match_array [hub.id, other_hub.id]
    end

    it "returns 404 for a nonexistent order cycle" do
      get "/api/v1/order_cycles/0", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(json_response[:errors]).to be_present
    end
  end

  describe "listing and pagination" do
    it "includes closed, upcoming and undated cycles in ID order" do
      closed = create(:closed_order_cycle, coordinator: hub)
      upcoming = create(:upcoming_order_cycle, coordinator: hub)
      undated = create(:undated_order_cycle, coordinator: hub)

      get "/api/v1/order_cycles", headers: headers

      expected_ids = [order_cycle, closed, upcoming, undated].map { |cycle| cycle.id.to_s }
      expect(response_ids).to eq expected_ids

      get "/api/v1/order_cycles/#{undated.id}", headers: headers

      expect(json_response[:data][:attributes]).
        to include(orders_open_at: nil, orders_close_at: nil)
    end

    it "paginates the visible cycles with matching metadata and links" do
      second_cycle = create(:simple_order_cycle, coordinator: hub)

      get "/api/v1/order_cycles", params: { page: 2, per_page: 1 }, headers: headers

      expect(response_ids).to eq [second_cycle.id.to_s]
      expect(json_response.dig(:meta, :pagination)).
        to include(results: 2, pages: 2, page: 2, per_page: 1)
      expect(json_response[:links][:prev]).to include("page=1")
      expect(json_response[:links][:next]).to be_nil
    end

    it "returns an empty collection for a hub manager without order cycles" do
      empty_hub = create(:distributor_enterprise)
      login_as empty_hub.owner

      get "/api/v1/order_cycles"

      expect(response).to have_http_status(:ok)
      expect(response_ids).to eq []
      expect(json_response.dig(:meta, :pagination, :results)).to eq 0
    end
  end
end

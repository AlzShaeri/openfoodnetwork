# frozen_string_literal: true

require 'open_food_network/order_cycle_permissions'

module Api
  module V1
    class OrderCycleSerializer < BaseSerializer
      attributes :id, :name, :orders_open_at, :orders_close_at, :coordinator_id

      attribute :distributor_ids do |order_cycle, params|
        visible_enterprises = OpenFoodNetwork::OrderCyclePermissions.
          new(params[:current_user], order_cycle).
          visible_enterprises

        order_cycle.distributors.merge(visible_enterprises).order(:id).pluck(:id)
      end
    end
  end
end

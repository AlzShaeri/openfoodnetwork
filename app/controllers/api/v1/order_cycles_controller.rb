# frozen_string_literal: true

module Api
  module V1
    class OrderCyclesController < BaseController
      before_action :authorize_index

      def index
        @pagy, order_cycles = pagy(visible_order_cycles.order(:id), **pagy_options)

        render json: OrderCycleSerializer.new(
          order_cycles,
          pagination_options.merge(params: { current_user: current_api_user })
        )
      end

      def show
        order_cycle = visible_order_cycles.find(params.expect(:id))
        authorize! :read, order_cycle

        render json: OrderCycleSerializer.new(
          order_cycle,
          params: { current_user: current_api_user }
        )
      end

      private

      def authorize_index
        authorize! :index, OrderCycle
      end

      def visible_order_cycles
        OrderCycle.where(id: OrderCycle.visible_by(current_api_user).reselect(:id))
      end
    end
  end
end

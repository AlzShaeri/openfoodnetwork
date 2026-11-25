# frozen_string_literal: true

class OrderCycleSchema < JsonApiSchema
  def self.object_name
    "order_cycle"
  end

  def self.attributes
    {
      id: { type: :integer, example: 1 },
      name: { type: :string, example: "Weekly order cycle" },
      orders_open_at: {
        type: :string, format: "date-time", nullable: true,
        example: "2026-11-01T00:00:00Z"
      },
      orders_close_at: {
        type: :string, format: "date-time", nullable: true,
        example: "2026-11-08T00:00:00Z"
      },
      coordinator_id: { type: :integer, example: 2 },
      distributor_ids: {
        type: :array,
        items: { type: :integer },
        example: [2, 3]
      }
    }
  end
end

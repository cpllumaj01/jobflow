class EstimatePdf
  include ActiveSupport::NumberHelper

  def initialize(estimate)
    @estimate = estimate
    @job = estimate.job
    @customer = @job.customer
  end

  def render
    pdf = Prawn::Document.new(page_size: "LETTER", margin: [ 48, 48, 60, 48 ])
    pdf.font_families.update("DejaVu" => {
      normal: Rails.root.join("app/assets/fonts/DejaVuSans.ttf").to_s,
      bold: Rails.root.join("app/assets/fonts/DejaVuSans-Bold.ttf").to_s
    })
    pdf.font "DejaVu", size: 10
    pdf.fill_color "0F172A"
    pdf.text "JobFlow", size: 16, style: :bold
    pdf.move_down 12
    pdf.text "Estimate ##{@estimate.id}", size: 26, style: :bold
    pdf.text "Status: #{@estimate.status.humanize}", leading: 6
    detail(pdf, "Expires", @estimate.expires_on&.to_fs(:long))

    section(pdf, "Customer")
    [ @customer.name, @customer.contact_name, @customer.email, @customer.phone, @customer.address ].each do |value|
      pdf.text value, leading: 3 if value.present?
    end

    section(pdf, "Job")
    pdf.text @job.name, style: :bold
    detail(pdf, "Job address", @job.address)
    detail(pdf, "Start date", @job.start_date&.to_fs(:long))
    detail(pdf, "Estimated completion", @job.estimated_completion_date&.to_fs(:long))
    pdf.text @job.description, leading: 3 if @job.description.present?

    section(pdf, "Line items")
    rows = @estimate.estimate_line_items.map do |item|
      [ item.description, number_to_delimited(item.quantity.to_s("F")),
        number_to_currency(item.unit_price), number_to_currency(item.line_total) ]
    end
    if rows.empty?
      pdf.text "No line items yet."
    else
      pdf.table([ [ "Description", "Quantity", "Unit price", "Line total" ], *rows ],
        header: true, width: pdf.bounds.width, column_widths: [ 246, 66, 78, 126 ],
        cell_style: { size: 9, padding: 8, border_color: "CBD5E1", borders: [ :bottom ] }) do |table|
        table.row(0).font_style = :bold
        table.row(0).background_color = "F1F5F9"
        table.columns(1..3).align = :right
      end
    end

    pdf.start_new_page if pdf.cursor < 60
    pdf.move_down 18
    pdf.text "Estimate total: #{number_to_currency(@estimate.total)}", size: 16, style: :bold, align: :right
    if @estimate.notes.present?
      section(pdf, "Notes")
      pdf.text @estimate.notes, leading: 4
    end
    pdf.number_pages "JobFlow | Estimate ##{@estimate.id} | Page <page> of <total>",
      at: [ 0, -25 ], width: pdf.bounds.width, align: :right, size: 8, color: "64748B"
    pdf.render
  end

  private
    def section(pdf, title)
      pdf.start_new_page if pdf.cursor < 65
      pdf.move_down 20
      pdf.text title, size: 12, style: :bold
      pdf.move_down 8
    end

    def detail(pdf, label, value)
      pdf.text "#{label}: #{value}", leading: 3 if value.present?
    end
end

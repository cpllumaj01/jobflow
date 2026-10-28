module AccountSecurityHelper
  def authenticator_qr_code(provisioning_uri)
    svg = RQRCode::QRCode.new(provisioning_uri).as_svg(viewbox: true, module_size: 4, offset: 16)
    image_tag "data:image/svg+xml;base64,#{Base64.strict_encode64(svg)}",
      alt: "Scan this QR code with your authenticator app", width: 256, height: 256,
      class: "mx-auto mt-4 h-auto w-full max-w-64 bg-white"
  end
end

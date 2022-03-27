resource "tls_private_key" "ca_key" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

resource "local_file" "ca_key" {
  content  = "${tls_private_key.ca_key.private_key_pem}"
  filename = "${local.keys_path}/ca_key.pem"
}

resource "tls_self_signed_cert" "ca_cert" {
  key_algorithm     = "RSA"
  private_key_pem   = "${tls_private_key.ca_key.private_key_pem}"
  is_ca_certificate = true

  subject {
    common_name         = "Kandula Self Signed CA"
    organization        = "Kandula Inc."
  }

  validity_period_hours = 50000

  allowed_uses = [
    "digital_signature",
    "cert_signing",
    "crl_signing",
  ]
}

resource "local_file" "ca_cert" {
  content  = "${tls_self_signed_cert.ca_cert.cert_pem}"
  filename = "${local.keys_path}/ca_cert.pem"
}

resource "tls_private_key" "kandula_key" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

resource "local_file" "kandula_key" {
  content  = "${tls_private_key.kandula_key.private_key_pem}"
  filename = "${local.keys_path}/kandula_key.pem"
}

resource "tls_cert_request" "kandula" {
  key_algorithm   = "RSA"
  private_key_pem = "${tls_private_key.kandula_key.private_key_pem}"

  subject {
    common_name         = "Kandula App"
    organization        = "Kandula Inc."
  }
}

resource "tls_locally_signed_cert" "kandula_cert" {
  cert_request_pem   = "${tls_cert_request.kandula.cert_request_pem}"
  ca_key_algorithm   = "RSA"
  ca_private_key_pem = "${tls_private_key.ca_key.private_key_pem}"
  ca_cert_pem        = "${tls_self_signed_cert.ca_cert.cert_pem}"

  validity_period_hours = 50000

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
    "client_auth",
  ]
}

resource "local_file" "kandula_cert" {
  content  = "${tls_locally_signed_cert.kandula_cert.cert_pem}"
  filename = "${local.keys_path}/kandula_cert.pem"
}

resource "aws_iam_server_certificate" "kandula_cert" {
  name             = "kandula_cert"
  certificate_body = "${tls_locally_signed_cert.kandula_cert.cert_pem}"
  private_key      = "${tls_private_key.kandula_key.private_key_pem}"

  lifecycle {
    create_before_destroy = true
  }
}

# „Am uitat parola” (BE #42): codul pleacă pe email prin Amazon SES, de pe no-reply@<domeniu>. Identitatea domeniului cu
# Easy DKIM (3 CNAME), MAIL FROM pe mail.<domeniu> (MX + SPF, ca și SPF să fie aliniat cu domeniul pentru DMARC) și o
# politică DMARC doar de observare. Contul SES pornește în sandbox (doar adrese verificate); ieșirea din sandbox
# (production access) se cere separat, cu acordul lui Zoltan. SMS-ul prin AWS rămâne blocat de SCP-ul contului.

locals {
  mail_from_domain = "mail.${var.domain_name}"
}

resource "aws_sesv2_email_identity" "domain" {
  email_identity = var.domain_name

  # Easy DKIM cu cheie de 2048 de biți (implicit); SES generează cele 3 tokenuri pentru CNAME-urile de mai jos.
  dkim_signing_attributes {
    next_signing_key_length = "RSA_2048_BIT"
  }
}

resource "aws_route53_record" "dkim" {
  count   = 3
  zone_id = aws_route53_zone.this.zone_id
  name    = "${aws_sesv2_email_identity.domain.dkim_signing_attributes[0].tokens[count.index]}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 1800
  records = ["${aws_sesv2_email_identity.domain.dkim_signing_attributes[0].tokens[count.index]}.dkim.amazonses.com"]
}

resource "aws_sesv2_email_identity_mail_from_attributes" "domain" {
  email_identity         = aws_sesv2_email_identity.domain.email_identity
  mail_from_domain       = local.mail_from_domain
  behavior_on_mx_failure = "USE_DEFAULT_VALUE"
}

resource "aws_route53_record" "mail_from_mx" {
  zone_id = aws_route53_zone.this.zone_id
  name    = local.mail_from_domain
  type    = "MX"
  ttl     = 1800
  records = ["10 feedback-smtp.eu-north-1.amazonses.com"]
}

resource "aws_route53_record" "mail_from_spf" {
  zone_id = aws_route53_zone.this.zone_id
  name    = local.mail_from_domain
  type    = "TXT"
  ttl     = 1800
  records = ["v=spf1 include:amazonses.com ~all"]
}

resource "aws_route53_record" "dmarc" {
  zone_id = aws_route53_zone.this.zone_id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = 1800
  records = ["v=DMARC1; p=none;"]
}

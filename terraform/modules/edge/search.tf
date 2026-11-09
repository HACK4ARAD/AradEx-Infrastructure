# Google Search Console: verificarea domeniului (proprietatea „Domeniu”), ca site-ul să poată fi trimis la indexare.
resource "aws_route53_record" "google_site_verification" {
  count   = var.google_site_verification == "" ? 0 : 1
  zone_id = aws_route53_zone.this.zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = 300
  records = [var.google_site_verification]
}

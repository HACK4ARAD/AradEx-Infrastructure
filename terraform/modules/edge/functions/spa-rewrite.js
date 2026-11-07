// CloudFront Function (cloudfront-js-2.0), viewer-request, DOAR pe comportamentul default (S3).
// 1) www.<domeniu> -> 301 spre <domeniu>, același path.
// 2) Rutele SPA (/m/..., /w/...) -> /index.html. Fișierele (au punct în ultimul segment) rămân neatinse.
// Nu se aplică pe /api/*, ca erorile API să rămână JSON.
function handler(event) {
  var request = event.request;
  var host = request.headers.host ? request.headers.host.value : '';

  if (host.indexOf('www.') === 0) {
    return {
      statusCode: 301,
      statusDescription: 'Moved Permanently',
      headers: { location: { value: 'https://' + host.substring(4) + request.uri } },
    };
  }

  var lastSegment = request.uri.substring(request.uri.lastIndexOf('/') + 1);
  if (lastSegment.indexOf('.') === -1) {
    request.uri = '/index.html';
  }
  return request;
}

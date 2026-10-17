/// Google Maps' dark look in the app's own purples, so the map sits with the rest of the dark theme. Light mode uses
/// Google's standard style. Applied through GoogleMap(style: ...).
const String kDarkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#1a1530"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#b4abd0"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0d0a17"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#2a2340"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#221b3a"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#9189ac"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#1d2a2a"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#2d2548"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#1f1930"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#a79ec2"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3d3260"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#2a2340"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0d0a17"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#786f92"}]}
]
''';

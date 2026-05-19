import 'dart:convert';
import 'package:http/http.dart' as http;

class GiphyGif {
  final String id;
  final String originalUrl;  // Para enviar en el mensaje
  final String previewUrl;   // Para mostrar en el grid (más liviana)

  const GiphyGif({
    required this.id,
    required this.originalUrl,
    required this.previewUrl,
  });

  factory GiphyGif.fromJson(Map<String, dynamic> json) {
    final images = json['images'] as Map<String, dynamic>;
    return GiphyGif(
      id: json['id'] as String,
      originalUrl: images['original']['url'] as String,
      previewUrl: (images['fixed_height_downsampled']?['url'] ??
          images['fixed_height']['url']) as String,
    );
  }
}

class GiphyService {
  static const _apiKey = 'R1DCLQz5U9fXy8ZDWTV2byatXNYvJ396';
  static const _base = 'https://api.giphy.com/v1/gifs';
  static const _limit = 24;

  Future<List<GiphyGif>> trending() async {
    final uri = Uri.parse(
        '$_base/trending?api_key=$_apiKey&limit=$_limit&rating=g');
    return _fetch(uri);
  }

  Future<List<GiphyGif>> search(String query) async {
    if (query.trim().isEmpty) return trending();
    final uri = Uri.parse(
        '$_base/search?api_key=$_apiKey'
        '&q=${Uri.encodeComponent(query)}&limit=$_limit&rating=g');
    return _fetch(uri);
  }

  Future<List<GiphyGif>> _fetch(Uri uri) async {
    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) return [];
      final data = (jsonDecode(res.body)['data'] as List)
          .cast<Map<String, dynamic>>();
      return data.map(GiphyGif.fromJson).toList();
    } catch (_) {
      return [];
    }
  }
}

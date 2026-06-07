import 'dart:convert';
import 'package:http/http.dart' as http;

// CONFIG
const String baseUrl = 'http://192.168.0.106:8096';
const String apiKey = 'ffcc2e0d2e774ba78e2829f1cb5b64ad';
const String userId = '263161d06b764a749881a6c0b9faf076';

// FETCH SONGS
Future<List<dynamic>> fetchSongs() async {
  const url = '$baseUrl/Users/$userId/Items'
      '?IncludeItemTypes=Audio'
      '&Recursive=true'
      '&Fields=PrimaryImageAspectRatio,SortName,Album,AlbumId,ParentId,RunTimeTicks'
      '&SortBy=SortName'
      '&api_key=$apiKey';

  final http.Response res = await http.get(Uri.parse(url));

  if (res.statusCode == 200) {
    final data = json.decode(res.body);
    return (data['Items'] as List<dynamic>?) ?? <dynamic>[];
  } else {
    throw Exception('Failed to load songs');
  }
}

// FETCH ALBUMS (FIXED)
Future<List<dynamic>> fetchAlbums() async {
  const url = '$baseUrl/Users/$userId/Items'
      '?IncludeItemTypes=MusicAlbum'
      '&Recursive=true'
      '&Fields=PrimaryImageAspectRatio,SortName,AlbumArtist,ChildCount'
      '&SortBy=SortName'
      '&SortOrder=Ascending'
      '&api_key=$apiKey';

  final http.Response res = await http.get(Uri.parse(url));

  if (res.statusCode == 200) {
    final data = json.decode(res.body);
    final List<dynamic> items = (data['Items'] as List<dynamic>?) ?? <dynamic>[];

    //  FILTER CLEAN ALBUMS ONLY
    final List<dynamic> albums = items.where((dynamic item) {
      return item['Type'] == 'MusicAlbum' && item['Id'] != null && item['Name'] != null;
    }).toList();

    return albums;
  } else {
    throw Exception('Failed to load albums');
  }
}

//  FETCH SONGS INSIDE ALBUM
Future<List<dynamic>> fetchAlbumSongs(String albumId) async {
  final url = '$baseUrl/Users/$userId/Items'
      '?ParentId=$albumId'
      '&IncludeItemTypes=Audio'
      '&Recursive=true'
      '&Fields=PrimaryImageAspectRatio,RunTimeTicks,SortName,Album,AlbumId,ParentId'
      '&SortBy=ParentIndexNumber,IndexNumber,SortName'
      '&api_key=$apiKey';

  final http.Response res = await http.get(Uri.parse(url));

  if (res.statusCode == 200) {
    final data = json.decode(res.body);
    return (data['Items'] as List<dynamic>?) ?? <dynamic>[];
  } else {
    throw Exception('Failed to load album songs');
  }
}

//  IMAGE URL
String getImageUrl(String id) {
  return '$baseUrl/Items/$id/Images/Primary?api_key=$apiKey';
}

String getStaticAudioUrl(String id) {
  return '$baseUrl/Audio/$id/stream?static=true&api_key=$apiKey';
}

List<String> audioStreamUrlCandidates(String id) {
  return <String>[getStaticAudioUrl(id)];
}

//  AUDIO URL (WORKING)
String getAudioUrl(String id) {
  return audioStreamUrlCandidates(id).first;
}

import 'package:image_picker/image_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

Future<XFile?> generateVideoThumbnail(XFile xfile) async {
  final thumbPath = await VideoThumbnail.thumbnailFile(
    video: xfile.path,
    imageFormat: ImageFormat.JPEG,
    maxHeight: 400,
    quality: 80,
  );
  return thumbPath == null ? null : XFile(thumbPath);
}

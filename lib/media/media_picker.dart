import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// Abstraction over the real picker plugins so [EditDeckScreen] can be
/// tested with a fake — neither `image_picker` nor `file_picker` has a
/// platform channel handler in a plain `flutter_test` host.
abstract class MediaPicker {
  Future<String?> pickImage();
  Future<String?> pickAudio();
}

class DevicePicker implements MediaPicker {
  final _imagePicker = ImagePicker();

  @override
  Future<String?> pickImage() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    return picked?.path;
  }

  @override
  Future<String?> pickAudio() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    return result?.files.single.path;
  }
}

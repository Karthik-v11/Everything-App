import 'package:everything_app/data/models/json_response.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

/// [GemmaService] is the on-device model's plugin boundary (Phase 13).
///
/// It owns exactly one thing: the lifecycle of a single downloaded LLM —
/// install, load, generate, unload, uninstall. It holds no app data, reads no
/// DAO, and knows nothing about tasks or transactions. Everything that decides
/// *what* to ask the model lives in [ModelBackedAiRepository]; everything that
/// decides *whether* there is a model to ask lives here.
///
/// ## Why this is a thin, untested class
///
/// Every method is a call into `flutter_gemma`'s statics, which cannot be faked
/// — so a test here would assert that the plugin does what the plugin does. The
/// judgement worth testing (which prompt, what to do when the model is absent or
/// answers badly) is pushed into [AiPrompt] and [ModelBackedAiRepository], both
/// of which are pure or fakeable. This is the same split Phase 12 used for
/// `ShareService`: test the boundary's shape, not the plugin.
///
/// ## The model is downloaded, never bundled
///
/// 584 MB of weights in the APK/IPA is not a shippable app, so the model arrives
/// on demand and the app is fully functional before it does — the rule-based
/// engine answers everything until then, and keeps answering the parsers even
/// after (see [ModelBackedAiRepository]). Every failure here is therefore a
/// *degradation*, never an error the user has to act on: no model means the
/// Phase 10 engine, which is the app's normal, shipped behaviour.
class GemmaService {
  GemmaService();

  /// The model's file on HuggingFace, and the reason it is spelled out rather
  /// than taken from `flutter_gemma`'s README.
  ///
  /// The package's documented example URL — `.../Gemma3-1B-IT/resolve/main/
  /// model.litertlm` — **does not exist**; that repository has no file by that
  /// name, and the request 401s before the filename is ever reached, so the
  /// error names the gate rather than the typo. The real generic CPU build is
  /// this one: `q4` quantisation, a 4096-token context, and no chipset suffix.
  ///
  /// The chipset-suffixed siblings in the same repo (`_sm8650`, `_mt6989`,
  /// `_Google_Tensor_G5`) are NPU builds for one SoC each and will not load on
  /// anything else, which is why the portable `multi-prefill-seq` build is the
  /// only sane default for a shipped app.
  static const String modelFile =
      'Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm';

  static const String _modelUrl =
      'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/'
      '$modelFile';

  /// The download is ~584 MB. Stated so the UI can warn *before* the download
  /// rather than after 584 MB of someone's mobile data.
  static const int modelSizeBytes = 584 * 1000 * 1000;

  /// [huggingFaceToken] gates the download. `litert-community/Gemma3-1B-IT` is a
  /// `gated: auto` repository — every request without a token 401s — so this is
  /// a deployment dependency of exactly the same kind as `WEATHER_API_KEY` and
  /// `NEWS_API_KEY`, and it is handled the same way: absent, the app is a working
  /// app minus its on-device model, and says so, rather than a broken one
  /// (Phase 6, note 5).
  ///
  /// It is read here rather than added to `core/utils/constants.dart` alongside
  /// the other two keys, because that file is protected (CLAUDE.md §0). Moving it
  /// there is a one-line developer change and the natural home for it.
  static String get huggingFaceToken =>
      dotenv.get('HF_TOKEN', fallback: '');

  InferenceModel? _model;

  /// [isLoaded] is whether the model is in memory and can answer *now*.
  ///
  /// Distinct from [isInstalled], which is only whether 584 MB is on disk:
  /// loading it costs seconds and hundreds of MB of RAM, so the two are separate
  /// questions and the assistant falls back to the rule-based engine for both.
  bool get isLoaded => _model != null;

  /// [isInstalled] is whether the weights are on disk.
  Future<bool> isInstalled() async {
    try {
      return await FlutterGemma.isModelInstalled(modelFile);
    } on Exception {
      return false;
    }
  }

  /// [install] downloads the model, reporting progress as a percentage.
  ///
  /// It does not load it — [load] is a separate cost the caller decides when to
  /// pay.
  Future<JsonResponse> install({
    required void Function(int percent) onProgress,
  }) async {
    final token = huggingFaceToken;
    if (token.isEmpty) {
      return JsonResponse.failure(
        statusCode: 401,
        message:
            'No HuggingFace token. Add HF_TOKEN to .env to download the model.',
      );
    }

    try {
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
      )
          .fromNetwork(_modelUrl, token: token)
          .withProgress(onProgress)
          .install();

      return JsonResponse.created(message: 'Model downloaded.');
    } on DownloadException catch (error) {
      // The gated-repo 401/403 is the likely failure and deserves its own words:
      // "download failed" would send someone looking at their connection when the
      // real answer is that their token cannot read that repository.
      return JsonResponse.failure(
        statusCode: 403,
        message: 'Error: The model download was refused (${error.runtimeType}). '
            'Check that HF_TOKEN can access litert-community/Gemma3-1B-IT.',
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: The model could not be downloaded.',
      );
    }
  }

  /// [load] brings the downloaded model into memory.
  Future<JsonResponse> load() async {
    if (_model != null) return JsonResponse.success(message: 'Already loaded.');

    try {
      _model = await FlutterGemma.getActiveModel(
        maxTokens: _maxTokens,
        preferredBackend: PreferredBackend.cpu,
      );
      return JsonResponse.success(message: 'Model ready.');
    } on Exception {
      _model = null;
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: The model could not be loaded.',
      );
    }
  }

  /// [generate] runs one prompt and returns the model's text.
  ///
  /// A **fresh session per call, closed straight after** — deliberately, not for
  /// tidiness. The two things the model backs (a document summary, an answer
  /// grounded in a search) are each self-contained: there is no conversation to
  /// carry, and a retained session would let one document's text leak into the
  /// next question's context, which for an app holding a vault and bank details
  /// is a real hazard rather than a hypothetical one. `createSession` shares the
  /// loaded weights, so the cost is a KV-cache reset rather than a reload.
  ///
  /// [temperature] is low: both callers want the model to restate given facts,
  /// not to be interesting about them.
  Future<JsonResponse> generate(
    String prompt, {
    String? systemInstruction,
    int maxOutputTokens = 256,
  }) async {
    final model = _model;
    if (model == null) {
      return JsonResponse.failure(
        statusCode: 503,
        message: 'Error: The model is not loaded.',
      );
    }

    InferenceModelSession? session;
    try {
      session = await model.createSession(
        temperature: 0.3,
        topK: 40,
        systemInstruction: systemInstruction,
        maxOutputTokens: maxOutputTokens,
      );
      await session.addQueryChunk(Message.text(text: prompt, isUser: true));
      final response = await session.getResponse();

      return JsonResponse.success(message: 'Generated.', data: response.trim());
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: The model could not answer.',
      );
    } finally {
      // The session holds native memory; an un-closed one on the error path is a
      // leak that only shows up as an OOM several questions later.
      await session?.close();
    }
  }

  /// [unload] frees the model's memory but leaves the download on disk.
  Future<void> unload() async {
    final model = _model;
    _model = null;
    try {
      await model?.close();
    } on Exception {
      // Nothing to report and nothing to do: the field is already cleared, so the
      // app has forgotten the model either way.
    }
  }

  /// [uninstall] unloads the model and deletes the 584 MB from disk.
  Future<JsonResponse> uninstall() async {
    await unload();
    try {
      await FlutterGemma.uninstallModel(modelFile);
      await FlutterGemma.clearActiveInferenceIdentity();
      return JsonResponse.success(message: 'Model removed.');
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: The model could not be removed.',
      );
    }
  }

  /// The context window. 2048 covers a grounded answer's search results or a
  /// document's opening comfortably, and costs less RAM than the 4096 the file
  /// supports — the summariser truncates its input to match (see [AiPrompt]).
  static const int _maxTokens = 2048;
}

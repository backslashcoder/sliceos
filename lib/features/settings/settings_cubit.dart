import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sliceos_engine/sliceos_engine.dart';

class SettingsState {
  const SettingsState({this.capabilities});

  /// Null while the engine is being probed.
  final EngineCapabilities? capabilities;

  bool get isLoading => capabilities == null;
}

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._engine) : super(const SettingsState());

  final VideoEngine _engine;

  /// Probes the processing engine. Safe to call again after the user installs
  /// or moves the native tools.
  Future<void> load() async {
    emit(const SettingsState());
    final capabilities = await _engine.capabilities();
    if (!isClosed) emit(SettingsState(capabilities: capabilities));
  }
}

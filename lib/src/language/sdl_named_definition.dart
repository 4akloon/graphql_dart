import 'sdl_definition.dart';

abstract interface class SDLNamedDefinition<
    T extends SDLNamedDefinition<dynamic>> implements SDLDefinition<T> {
  String get name;
}

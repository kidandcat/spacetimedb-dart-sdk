import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:spacetimedb_sdk/spacetimedb.dart';

import '../generated/module.dart';

class SpacetimeDbService extends ChangeNotifier {
  SpacetimeDbClient? _client;
  RemoteReducers? _reducers;

  // Table handles
  UserTableHandle? _users;
  ServerTableHandle? _servers;
  ChannelTableHandle? _channels;
  MessageTableHandle? _messages;
  DirectMessageTableHandle? _directMessages;
  ServerMemberTableHandle? _serverMembers;
  VoiceStateTableHandle? _voiceStates;
  UserSettingsTableHandle? _userSettings;

  // Typed accessors
  UserTableHandle get users => _users!;
  ServerTableHandle get servers => _servers!;
  ChannelTableHandle get channels => _channels!;
  MessageTableHandle get messages => _messages!;
  DirectMessageTableHandle get directMessages => _directMessages!;
  ServerMemberTableHandle get serverMembers => _serverMembers!;
  VoiceStateTableHandle get voiceStates => _voiceStates!;
  UserSettingsTableHandle get userSettings => _userSettings!;
  RemoteReducers get reducers => _reducers!;

  // Connection state
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  String? _connectionError;
  String? get connectionError => _connectionError;

  // Identity
  Identity? _myIdentity;
  Identity? get myIdentity => _myIdentity;
  Token? _myToken;
  Token? get myToken => _myToken;

  // UI state
  int? _selectedServerId;
  int? get selectedServerId => _selectedServerId;

  int? _selectedChannelId;
  int? get selectedChannelId => _selectedChannelId;

  Identity? _selectedDmUser;
  Identity? get selectedDmUser => _selectedDmUser;

  bool _showDms = false;
  bool get showDms => _showDms;

  bool _showMemberList = true;
  bool get showMemberList => _showMemberList;

  // Getters for current context
  User? get currentUser {
    if (_myIdentity == null || _users == null) return null;
    return _users!.findByIdentity(_myIdentity!);
  }

  Server? get selectedServer {
    if (_selectedServerId == null || _servers == null) return null;
    return _servers!.rows.where((s) => s.id == _selectedServerId).firstOrNull;
  }

  Channel? get selectedChannel {
    if (_selectedChannelId == null || _channels == null) return null;
    return _channels!.rows.where((c) => c.id == _selectedChannelId).firstOrNull;
  }

  List<Server> get myServers {
    if (_servers == null || _serverMembers == null || _myIdentity == null) {
      return [];
    }
    final memberServerIds = _serverMembers!.rows
        .where((m) => m.identity == _myIdentity)
        .map((m) => m.serverId)
        .toSet();
    return _servers!.rows.where((s) => memberServerIds.contains(s.id)).toList();
  }

  List<Channel> get currentChannels {
    if (_selectedServerId == null || _channels == null) return [];
    return _channels!.rows
        .where((c) => c.serverId == _selectedServerId)
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));
  }

  List<Channel> get currentTextChannels =>
      currentChannels.where((c) => c.channelType == ChannelType.text).toList();

  List<Channel> get currentVoiceChannels =>
      currentChannels.where((c) => c.channelType == ChannelType.voice).toList();

  List<Message> get currentMessages {
    if (_selectedChannelId == null || _messages == null) return [];
    return _messages!.rows
        .where((m) => m.channelId == _selectedChannelId)
        .toList()
      ..sort((a, b) => a.sentAt.microsecondsSinceEpoch
          .compareTo(b.sentAt.microsecondsSinceEpoch));
  }

  List<ServerMember> get currentMembers {
    if (_selectedServerId == null || _serverMembers == null) return [];
    return _serverMembers!.rows
        .where((m) => m.serverId == _selectedServerId)
        .toList();
  }

  List<VoiceState> get currentVoiceUsers {
    if (_selectedChannelId == null || _voiceStates == null) return [];
    return _voiceStates!.rows
        .where((v) => v.channelId == _selectedChannelId)
        .toList();
  }

  List<VoiceState> voiceUsersInChannel(int channelId) {
    if (_voiceStates == null) return [];
    return _voiceStates!.rows
        .where((v) => v.channelId == channelId)
        .toList();
  }

  User? getUserByIdentity(Identity identity) {
    return _users?.findByIdentity(identity);
  }

  List<DirectMessage> getDmsWith(Identity other) {
    if (_directMessages == null || _myIdentity == null) return [];
    return _directMessages!.rows
        .where((dm) =>
            (dm.sender == _myIdentity && dm.receiver == other) ||
            (dm.sender == other && dm.receiver == _myIdentity))
        .toList()
      ..sort((a, b) => a.sentAt.microsecondsSinceEpoch
          .compareTo(b.sentAt.microsecondsSinceEpoch));
  }

  /// Unique DM conversation partners.
  List<Identity> get dmConversations {
    if (_directMessages == null || _myIdentity == null) return [];
    final partners = <Identity>{};
    for (final dm in _directMessages!.rows) {
      if (dm.sender == _myIdentity) {
        partners.add(dm.receiver);
      } else if (dm.receiver == _myIdentity) {
        partners.add(dm.sender);
      }
    }
    return partners.toList();
  }

  // UI actions
  void selectServer(int serverId) {
    _showDms = false;
    _selectedServerId = serverId;
    _selectedDmUser = null;
    // Auto-select first text channel
    final textChannels = _channels?.rows
        .where(
            (c) => c.serverId == serverId && c.channelType == ChannelType.text)
        .toList()
      ?..sort((a, b) => a.position.compareTo(b.position));
    _selectedChannelId = textChannels?.firstOrNull?.id;
    notifyListeners();
  }

  void selectChannel(int channelId) {
    _selectedChannelId = channelId;
    notifyListeners();
  }

  void showDirectMessages() {
    _showDms = true;
    _selectedServerId = null;
    _selectedChannelId = null;
    _selectedDmUser = null;
    notifyListeners();
  }

  void selectDmUser(Identity identity) {
    _showDms = true;
    _selectedServerId = null;
    _selectedChannelId = null;
    _selectedDmUser = identity;
    notifyListeners();
  }

  void toggleMemberList() {
    _showMemberList = !_showMemberList;
    notifyListeners();
  }

  // Connection
  Future<void> connect(String host, String database) async {
    _connectionError = null;
    notifyListeners();

    try {
      _client = SpacetimeDbClient.builder()
          .withUri(host)
          .withDatabase(database)
          .withAutoReconnect(true)
          .withMaxReconnectAttempts(10)
          .build();

      // Create table caches
      final userCache = UserTableHandle.createCache();
      final serverCache = ServerTableHandle.createCache();
      final channelCache = ChannelTableHandle.createCache();
      final messageCache = MessageTableHandle.createCache();
      final dmCache = DirectMessageTableHandle.createCache();
      final memberCache = ServerMemberTableHandle.createCache();
      final voiceCache = VoiceStateTableHandle.createCache();
      final settingsCache = UserSettingsTableHandle.createCache();

      // Register caches
      _client!.registerTableCache(userCache);
      _client!.registerTableCache(serverCache);
      _client!.registerTableCache(channelCache);
      _client!.registerTableCache(messageCache);
      _client!.registerTableCache(dmCache);
      _client!.registerTableCache(memberCache);
      _client!.registerTableCache(voiceCache);
      _client!.registerTableCache(settingsCache);

      // Create typed handles
      _users = UserTableHandle(userCache);
      _servers = ServerTableHandle(serverCache);
      _channels = ChannelTableHandle(channelCache);
      _messages = MessageTableHandle(messageCache);
      _directMessages = DirectMessageTableHandle(dmCache);
      _serverMembers = ServerMemberTableHandle(memberCache);
      _voiceStates = VoiceStateTableHandle(voiceCache);
      _userSettings = UserSettingsTableHandle(settingsCache);

      // Create reducers
      _reducers = RemoteReducers(
        callReducer: _client!.callReducer,
        onReducer: _client!.onReducer,
      );

      // Listen for identity
      _client!.onIdentityReceived = (identity, token, connectionId) {
        _myIdentity = identity;
        _myToken = token;
        _isConnected = true;
        notifyListeners();
      };

      _client!.onDisconnect = (_) {
        _isConnected = false;
        notifyListeners();
      };

      // Register table change listeners for UI updates
      _users!.onInsert((_) => notifyListeners());
      _users!.onUpdate((_, _) => notifyListeners());
      _users!.onDelete((_) => notifyListeners());

      _servers!.onInsert((_) => notifyListeners());
      _servers!.onUpdate((_, _) => notifyListeners());
      _servers!.onDelete((_) => notifyListeners());

      _channels!.onInsert((_) => notifyListeners());
      _channels!.onUpdate((_, _) => notifyListeners());
      _channels!.onDelete((_) => notifyListeners());

      _messages!.onInsert((_) => notifyListeners());
      _messages!.onUpdate((_, _) => notifyListeners());
      _messages!.onDelete((_) => notifyListeners());

      _directMessages!.onInsert((_) => notifyListeners());

      _serverMembers!.onInsert((_) => notifyListeners());
      _serverMembers!.onDelete((_) => notifyListeners());

      _voiceStates!.onInsert((_) => notifyListeners());
      _voiceStates!.onUpdate((_, _) => notifyListeners());
      _voiceStates!.onDelete((_) => notifyListeners());

      // Connect
      await _client!.connect();

      // Subscribe to all tables
      _client!.subscribe([
        'SELECT * FROM user',
        'SELECT * FROM server',
        'SELECT * FROM channel',
        'SELECT * FROM message',
        'SELECT * FROM direct_message',
        'SELECT * FROM server_member',
        'SELECT * FROM voice_state',
        'SELECT * FROM user_roles',
        'SELECT * FROM user_settings',
      ]);
    } catch (e) {
      _connectionError = e.toString();
      notifyListeners();
    }
  }

  // Reducer wrappers
  Future<void> sendMessage(String content) async {
    if (_selectedChannelId == null) return;
    await _reducers!.sendMessage(_selectedChannelId!, content);
  }

  Future<void> sendDm(Identity receiver, String content) async {
    await _reducers!.sendDirectMessage(receiver, content);
  }

  Future<void> createServer(String name) async {
    await _reducers!.createServer(name, '');
  }

  Future<void> createChannel(
      int serverId, String name, ChannelType type, String topic) async {
    await _reducers!.createChannel(serverId, name, type, topic);
  }

  Future<void> joinServer(int serverId) async {
    await _reducers!.joinServer(serverId);
  }

  Future<void> leaveServer(int serverId) async {
    await _reducers!.leaveServer(serverId);
  }

  Future<void> setUsername(String username) async {
    await _reducers!.setUsername(username);
  }

  Future<void> updateProfile(
      String displayName, String avatarUrl, String statusText) async {
    await _reducers!.updateProfile(displayName, avatarUrl, statusText);
  }

  Future<void> joinVoiceChannel(int channelId) async {
    await _reducers!.joinVoiceChannel(channelId);
  }

  Future<void> leaveVoiceChannel() async {
    await _reducers!.leaveVoiceChannel();
  }

  Future<void> toggleMute() async {
    await _reducers!.toggleMute();
  }

  Future<void> toggleDeafen() async {
    await _reducers!.toggleDeafen();
  }

  Future<void> editMessage(int messageId, String content) async {
    await _reducers!.editMessage(messageId, content);
  }

  Future<void> deleteMessage(int messageId) async {
    await _reducers!.deleteMessage(messageId);
  }

  Future<void> deleteChannel(int channelId) async {
    await _reducers!.deleteChannel(channelId);
  }

  Future<void> deleteServer(int serverId) async {
    await _reducers!.deleteServer(serverId);
  }

  @override
  void dispose() {
    _client?.dispose();
    super.dispose();
  }
}

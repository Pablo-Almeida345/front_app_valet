import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

void main() {
  runApp(const ValetApp());
}

const String apiBaseUrl = 'http://127.0.0.1:8080';

// ==========================================
// CLIENTE HTTP NATIVO (SEM PACOTES EXTERNOS)
// ==========================================
Future> enviarRequisicao({
  required String metodo,
  required String caminho,
  required String token,
  Map<String, dynamic>? dados,
}) async {
  final HttpClient client = HttpClient();
  try {
    final Uri uri = Uri.parse('$apiBaseUrl$caminho');
    final HttpClientRequest request = await client.openUrl(metodo, uri);

    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');

    if (dados != null) {
      final List<int> bytes = utf8.encode(jsonEncode(dados));
      request.contentLength = bytes.length;
      request.add(bytes);
    }

    final HttpClientResponse response = await request.close();
    final String respostaTexto = await response.transform(utf8.decoder).join();

    return <String, dynamic>{
      'statusCode': response.statusCode,
      'body': respostaTexto,
    };
  } finally {
    client.close();
  }
}

class ValetApp extends StatelessWidget {
  const ValetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Controle de Pátio - Valet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
      ),
      home: const LoginTokenScreen(),
    );
  }
}

// ==========================================
// 1. TELA DE AUTENTICAÇÃO POR TOKEN
// ==========================================
class LoginTokenScreen extends StatefulWidget {
  const LoginTokenScreen({super.key});

  @override
  State<LoginTokenScreen> createState() => _LoginTokenScreenState();
}

class _LoginTokenScreenState extends State<LoginTokenScreen> {
  final TextEditingController _tokenController =
      TextEditingController(text: 'valet-token-2026');
  bool _validando = false;
  String? _erro;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    final String token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _erro = 'Informe o token de acesso.');
      return;
    }

    setState(() {
      _validando = true;
      _erro = null;
    });

    try {
      final Map<String, dynamic> res = await enviarRequisicao(
        metodo: 'GET',
        caminho: '/veiculos',
        token: token,
      );

      if (!mounted) return;

      if (res['statusCode'] == 200) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (BuildContext context) => PatioScreen(token: token),
          ),
        );
      } else {
        setState(() {
          _erro = 'Acesso negado: Token inválido (Erro ${res['statusCode']}).';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível conectar em $apiBaseUrl.\nInicie o back-end Dart primeiro.';
      });
    } finally {
      if (mounted) {
        setState(() => _validando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.local_parking,
                    size: 64,
                    color: Colors.indigo,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Acesso ao Valet',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _tokenController,
                    decoration: const InputDecoration(
                      labelText: 'Token do Operador',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.vpn_key),
                    ),
                  ),
                  if (_erro != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      _erro!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _validando ? null : _entrar,
                      child: _validando
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Entrar no Sistema'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 2. TELA PRINCIPAL DO PÁTIO (CRUD REAL)
// ==========================================
class PatioScreen extends StatefulWidget {
  final String token;
  const PatioScreen({super.key, required this.token});

  @override
  State<PatioScreen> createState() => _PatioScreenState();
}

class _PatioScreenState extends State<PatioScreen> {
  List> _veiculos = >[];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregarVeiculos();
  }

  Future<void> _carregarVeiculos() async {
    setState(() => _carregando = true);
    try {
      final Map<String, dynamic> res = await enviarRequisicao(
        metodo: 'GET',
        caminho: '/veiculos',
        token: widget.token,
      );

      if (res['statusCode'] == 200) {
        final List<dynamic> dados = jsonDecode(res['body'] as String) as List<dynamic>;
        if (!mounted) return;
        setState(() {
          _veiculos = dados
              .map((dynamic item) => Map<String, dynamic>.from(item as Map<dynamic, dynamic>))
              .toList();
        });
      } else {
        _mostrarAviso('Erro ao listar: ${res['statusCode']}');
      }
    } catch (e) {
      _mostrarAviso('Erro de conexão ao buscar veículos.');
    } finally {
      if (mounted) {
        setState(() => _carregando = false);
      }
    }
  }

  Future<void> _salvarVeiculo({
    int? id,
    required String marca,
    required String modelo,
    required int ano,
  }) async {
    try {
      final Map<String, dynamic> res = await enviarRequisicao(
        metodo: id == null ? 'POST' : 'PUT',
        caminho: id == null ? '/veiculos' : '/veiculos/$id',
        token: widget.token,
        dados: <String, dynamic>{
          'marca': marca,
          'modelo': modelo,
          'ano': ano,
        },
      );

      if (res['statusCode'] == 200 || res['statusCode'] == 201) {
        await _carregarVeiculos();
        _mostrarAviso(
          id == null ? 'Veículo salvo no banco!' : 'Dados atualizados no banco!',
        );
      } else {
        _mostrarAviso('Erro ao salvar: ${res['body']}');
      }
    } catch (e) {
      _mostrarAviso('Falha de conexão com o servidor.');
    }
  }

  Future<void> _excluirVeiculo(int id) async {
    try {
      final Map<String, dynamic> res = await enviarRequisicao(
        metodo: 'DELETE',
        caminho: '/veiculos/$id',
        token: widget.token,
      );

      if (res['statusCode'] == 200) {
        await _carregarVeiculos();
        _mostrarAviso('Baixa registrada no banco!');
      } else {
        _mostrarAviso('Erro ao excluir: ${res['body']}');
      }
    } catch (e) {
      _mostrarAviso('Erro de conexão ao dar baixa.');
    }
  }

  void _mostrarAviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _abrirFormulario({Map<String, dynamic>? veiculo}) {
    final TextEditingController marcaCtrl =
        TextEditingController(text: veiculo?['marca']?.toString() ?? '');
    final TextEditingController modeloCtrl =
        TextEditingController(text: veiculo?['modelo']?.toString() ?? '');
    final TextEditingController anoCtrl =
        TextEditingController(text: veiculo?['ano']?.toString() ?? '');

    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(veiculo == null ? 'Registrar Entrada' : 'Editar Veículo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: marcaCtrl,
              decoration: const InputDecoration(labelText: 'Marca (ex: Fiat)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: modeloCtrl,
              decoration: const InputDecoration(labelText: 'Modelo (ex: Argo)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: anoCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Ano (ex: 2024)'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final String marca = marcaCtrl.text.trim();
              final String modelo = modeloCtrl.text.trim();
              final int? ano = int.tryParse(anoCtrl.text.trim());
              if (marca.isEmpty || modelo.isEmpty || ano == null) return;

              Navigator.pop(ctx);
              _salvarVeiculo(
                id: veiculo?['id'] as int?,
                marca: marca,
                modelo: modelo,
                ano: ano,
              );
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Pátio Valet (${_veiculos.length})'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar lista do banco',
            onPressed: _carregarVeiculos,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const LoginTokenScreen(),
              ),
            ),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _veiculos.isEmpty
              ? const Center(
                  child: Text('Nenhum veículo cadastrado no banco.'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _veiculos.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Map<String, dynamic> v = _veiculos[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text('${v['id']}')),
                        title: Text('${v['marca']} ${v['modelo']}'),
                        subtitle: Text('Ano: ${v['ano']}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _abrirFormulario(veiculo: v),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _excluirVeiculo(v['id'] as int),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _abrirFormulario(),
        tooltip: 'Novo Veículo',
        child: const Icon(Icons.add),
      ),
    );
  }
}
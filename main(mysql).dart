import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<String> _labels = [];
  File? _image;
  String? _predictedLabel;
  double? _confidence;
  bool isLoading = false;
  Interpreter? _interpreter;
  Map<String, dynamic> _medicamentosData = {};
  Map<String, dynamic>? _medicamentoDetalles;

  @override
  void initState() {
    super.initState();
    loadModel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Selecciona un medicamento."),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.exit_to_app),
            onPressed: () {
              _mostrarDialogoSalir(context);
            },
          ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: 30),
                // Muestra imagen seleccionada
                _image == null
                    ? Container()
                    : Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Image.file(
                    _image!,
                    width: 300,
                    height: 300,
                    fit: BoxFit.cover,
                  ),
                ),
                SizedBox(height: 20),
                _predictedLabel != null
                    ? Column(
                  children: [
                    Text(
                      "$_predictedLabel\nConfianza: ${(_confidence! * 100).toStringAsFixed(2)}%",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22.0,
                        background: Paint()..color = Colors.deepPurple,
                      ),
                    ),
                    SizedBox(height: 20),
                    // Mostrar detalles del medicamento
                    _medicamentoDetalles != null
                        ? Column(
                      children: [
                        SizedBox(height: 20),
                        Text(
                          "Información del medicamento:",
                          style: TextStyle(
                            fontSize: 18.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          "- Nombre: ${_medicamentoDetalles!['nombre']}",
                          style: TextStyle(fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 5),
                        Text(
                          "- Dosis: ${_medicamentoDetalles!['dosis']}",
                          style: TextStyle(fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 5),
                        Text(
                          "- Indicaciones: ${_medicamentoDetalles!['indicaciones']}",
                          style: TextStyle(fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 5),
                        Text(
                          "- Contraindicaciones: ${_medicamentoDetalles!['contraindicaciones']}",
                          style: TextStyle(fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 5),
                        Text(
                          "- Efectos secundarios: ${_medicamentoDetalles!['efectos_secundarios']}",
                          style: TextStyle(fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    )
                        : Text("No se encontraron detalles para este medicamento."),
                  ],
                )
                    : Container(),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showImageSourceDialog(context),
        child: Icon(Icons.camera_alt),
      ),
    );
  }

  // Función para mostrar cámara o galería
  Future<void> showImageSourceDialog(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Selecciona la fuente de la imagen'),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await pickImage(ImageSource.camera);  // Usa cámara
              },
              child: Text('Cámara'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await pickImage(ImageSource.gallery);  // Usa galería
              },
              child: Text('Galería'),
            ),
          ],
        );
      },
    );
  }

  // Función para seleccionar la imagen cámara o galería
  Future<void> pickImage(ImageSource source) async {
    final XFile? image = await ImagePicker().pickImage(source: source);
    if (image == null) return;

    setState(() {
      isLoading = true;
      _image = File(image.path);
    });

    classifyImage(_image!);
  }

  // Función para cargar el modelo de TensorFlow Lite
  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/model_unquant.tflite');
      _labels = await loadLabels();
      print("Modelo cargado correctamente");
    } catch (e) {
      print("Error al cargar el modelo: $e");
    }
  }

  // Se obtienen los datos del medicamento desde PHP con get_medicamento.php
  Future<void> fetchMedicamentoDetails(String nombre) async {
    try {
      final response = await http.get(Uri.parse('https://siedm.com/get_medicamento.php?nombre=$nombre'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['error'] == null) {
          setState(() {
            _medicamentoDetalles = data;
          });
          print("Detalles del medicamento obtenidos");
        } else {
          print("Error: Medicamento no encontrado");
        }
      } else {
        print("Error al obtener datos del medicamento");
      }
    } catch (e) {
      print("Error de conexión: $e");
    }
  }

  // Función para clasificar la imagen con TFLite
  Future<void> classifyImage(File image) async {
    if (_interpreter == null) {
      print("El intérprete no está inicializado");
      return;
    }

    try {
      var inputImage = await preprocessImage(image); // Procesa la imagen
      var output = List.generate(1, (_) => List.filled(10, 0.0)); // Crea la salida para el modelo

      _interpreter!.run(inputImage, output); // Ejecuta la clasificación

      int maxIndex = getMaxConfidenceIndex(output[0]); // Obtiene el índice de la predicción con más confianza
      setState(() {
        isLoading = false;
        _predictedLabel = _labels[maxIndex]; // Almacena la etiqueta predicha
        _confidence = output[0][maxIndex]; // Almacena la confianza de la predicción
      });

      print("Predicción: $_predictedLabel con confianza de $_confidence");

      // Obtiene los detalles del medicamento a través de la función fetchMedicamentoDetails
      fetchMedicamentoDetails(_predictedLabel!);

    } catch (e) {
      print("Error al clasificar la imagen: $e");
      setState(() {
        isLoading = false; // Desactiva el indicador de carga
      });
    }
  }

  // Función para cargar las etiquetas desde el archivo labels.txt
  Future<List<String>> loadLabels() async {
    try {
      String labelData = await rootBundle.loadString('assets/labels.txt');
      List<String> lines = labelData.split('\n');
      List<String> labels = lines
          .where((line) => line.trim().isNotEmpty)
          .map((line) {
        List<String> parts = line.split(' ');
        return parts.length > 1 ? parts.sublist(1).join(' ') : '';
      }).where((label) => label.isNotEmpty).toList();

      print("Etiquetas cargadas: $labels");
      return labels;
    } catch (e) {
      print("Error al cargar etiquetas: $e");
      return [];
    }
  }

  // Función para preprocesar la imagen
  Future<List<List<List<List<double>>>>> preprocessImage(File image) async {
    Uint8List imageBytes = await image.readAsBytes(); // Lee la imagen en bytes
    img.Image? imageDecoded = img.decodeImage(imageBytes); // Decodifica la imagen
    img.Image resizedImage = img.copyResize(imageDecoded!, width: 224, height: 224); // Redimensiona

    List<List<List<double>>> normalizedPixels = [];
    for (int y = 0; y < resizedImage.height; y++) {
      List<List<double>> row = [];
      for (int x = 0; x < resizedImage.width; x++) {
        int pixel = resizedImage.getPixel(x, y); // Se obtiene el valor del pixel
        double r = img.getRed(pixel) / 255.0;
        double g = img.getGreen(pixel) / 255.0;
        double b = img.getBlue(pixel) / 255.0;
        row.add([r, g, b]); // Normaliza el pixel
      }
      normalizedPixels.add(row);
    }

    return [normalizedPixels];
  }

  // Función donde se obtiene el índice con mayor confianza de la salida
  int getMaxConfidenceIndex(List<double> output) {
    double maxConfidence = output.reduce((a, b) => a > b ? a : b); // Encuentra el valor máximo
    return output.indexOf(maxConfidence);
  }

  // Liberar recursos cuando se destruye el widget
  @override
  void dispose() {
    _interpreter?.close(); // Cierra el intérprete de TensorFlow Lite
    super.dispose();
  }

  void _mostrarDialogoSalir(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Confirmar salida"),
          content: Text("¿Estás seguro de que deseas salir de la aplicación?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(), // Cierra el diálogo
              child: Text("Cancelar"),
            ),
            TextButton(
              onPressed: () {
                // Cierra la aplicación según la plataforma
                if (Platform.isAndroid) {
                  SystemNavigator.pop();
                } else if (Platform.isIOS) {
                  exit(0);
                }
              },
              child: Text("Salir"),
            ),
          ],
        );
      },
    );
  }
}
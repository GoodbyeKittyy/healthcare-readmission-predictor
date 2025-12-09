import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const ReadmissionPredictorApp());
}

// MARK: - Models
class Patient {
  final String patientId;
  final String name;
  final int age;
  final int numComorbidities;
  final int priorAdmissions;
  final bool diabetes;
  final bool chf;
  final bool copd;
  final double socioeconomicIndex;
  final DateTime? admissionDate;

  Patient({
    required this.patientId,
    required this.name,
    required this.age,
    required this.numComorbidities,
    required this.priorAdmissions,
    required this.diabetes,
    required this.chf,
    required this.copd,
    required this.socioeconomicIndex,
    this.admissionDate,
  });

  factory Patient.fromJson(Map<String, dynamic> json) {
    return Patient(
      patientId: json['patient_id'] ?? '',
      name: json['name'] ?? '',
      age: json['age'] ?? 0,
      numComorbidities: json['num_comorbidities'] ?? 0,
      priorAdmissions: json['prior_admissions'] ?? 0,
      diabetes: json['diabetes'] ?? false,
      chf: json['chf'] ?? false,
      copd: json['copd'] ?? false,
      socioeconomicIndex: (json['socioeconomic_index'] ?? 50.0).toDouble(),
      admissionDate: json['admission_date'] != null 
          ? DateTime.parse(json['admission_date']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'patient_id': patientId,
      'name': name,
      'age': age,
      'num_comorbidities': numComorbidities,
      'prior_admissions': priorAdmissions,
      'diabetes': diabetes,
      'chf': chf,
      'copd': copd,
      'socioeconomic_index': socioeconomicIndex,
      'admission_date': admissionDate?.toIso8601String(),
    };
  }
}

class RiskAssessment {
  final int assessmentId;
  final String patientId;
  final double risk30Day;
  final double risk60Day;
  final double risk90Day;
  final double hazardRatio;
  final String riskCategory;
  final double confidenceLower;
  final double confidenceUpper;
  final DateTime assessmentDate;
  final CompetingRisks? competingRisks;
  final List<String>? carePlan;

  RiskAssessment({
    required this.assessmentId,
    required this.patientId,
    required this.risk30Day,
    required this.risk60Day,
    required this.risk90Day,
    required this.hazardRatio,
    required this.riskCategory,
    required this.confidenceLower,
    required this.confidenceUpper,
    required this.assessmentDate,
    this.competingRisks,
    this.carePlan,
  });

  factory RiskAssessment.fromJson(Map<String, dynamic> json) {
    return RiskAssessment(
      assessmentId: json['assessment_id'] ?? 0,
      patientId: json['patient_id'] ?? '',
      risk30Day: (json['risk_30_day'] ?? 0.0).toDouble(),
      risk60Day: (json['risk_60_day'] ?? 0.0).toDouble(),
      risk90Day: (json['risk_90_day'] ?? 0.0).toDouble(),
      hazardRatio: (json['hazard_ratio'] ?? 1.0).toDouble(),
      riskCategory: json['risk_category'] ?? 'low',
      confidenceLower: (json['confidence_lower'] ?? 0.0).toDouble(),
      confidenceUpper: (json['confidence_upper'] ?? 1.0).toDouble(),
      assessmentDate: json['assessment_date'] != null
          ? DateTime.parse(json['assessment_date'])
          : DateTime.now(),
      competingRisks: json['competing_risks'] != null
          ? CompetingRisks.fromJson(json['competing_risks'])
          : null,
      carePlan: json['care_plan'] != null
          ? List<String>.from(json['care_plan'])
          : null,
    );
  }

  Color get riskColor {
    switch (riskCategory) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }
}

class CompetingRisks {
  final double readmission;
  final double death;
  final double transfer;
  final double recovery;

  CompetingRisks({
    required this.readmission,
    required this.death,
    required this.transfer,
    required this.recovery,
  });

  factory CompetingRisks.fromJson(Map<String, dynamic> json) {
    return CompetingRisks(
      readmission: (json['readmission'] ?? 0.0).toDouble(),
      death: (json['death'] ?? 0.0).toDouble(),
      transfer: (json['transfer'] ?? 0.0).toDouble(),
      recovery: (json['recovery'] ?? 0.0).toDouble(),
    );
  }
}

// MARK: - API Service
class ReadmissionAPIService {
  final String baseUrl;
  final http.Client client;

  ReadmissionAPIService({
    this.baseUrl = 'http://localhost:3000',
    http.Client? client,
  }) : client = client ?? http.Client();

  Future<List<Patient>> fetchPatients() async {
    try {
      final response = await client.get(Uri.parse('$baseUrl/patients'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Patient.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load patients: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching patients: $e');
    }
  }

  Future<Patient> getPatient(String patientId) async {
    final response = await client.get(Uri.parse('$baseUrl/patients/$patientId'));
    if (response.statusCode == 200) {
      return Patient.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to load patient');
    }
  }

  Future<Patient> createPatient(Patient patient) async {
    final response = await client.post(
      Uri.parse('$baseUrl/patients'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(patient.toJson()),
    );
    
    if (response.statusCode == 200 || response.statusCode == 201) {
      return Patient.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to create patient');
    }
  }

  Future<RiskAssessment> assessPatientRisk(Patient patient) async {
    final requestBody = {
      'patientId': patient.patientId,
      'age': patient.age,
      'numComorbidities': patient.numComorbidities,
      'priorAdmissions': patient.priorAdmissions,
      'diabetes': patient.diabetes,
      'chf': patient.chf,
      'copd': patient.copd,
      'socioeconomicIndex': patient.socioeconomicIndex,
    };

    final response = await client.post(
      Uri.parse('$baseUrl/risk-assessment/${patient.patientId}'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(requestBody),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return RiskAssessment.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to assess risk');
    }
  }

  Future<List<RiskAssessment>> getRiskHistory(String patientId) async {
    final response = await client.get(
      Uri.parse('$baseUrl/risk-assessment/$patientId'),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => RiskAssessment.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load risk history');
    }
  }
}

// MARK: - Main App
class ReadmissionPredictorApp extends StatelessWidget {
  const ReadmissionPredictorApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Readmission Predictor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      home: const PatientListScreen(),
    );
  }
}

// MARK: - Patient List Screen
class PatientListScreen extends StatefulWidget {
  const PatientListScreen({Key? key}) : super(key: key);

  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen> {
  final ReadmissionAPIService _apiService = ReadmissionAPIService();
  List<Patient> _patients = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  Future<void> _loadPatients() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final patients = await _apiService.fetchPatients();
      setState(() {
        _patients = patients;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Readmission Predictor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPatients,
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => AddPatientScreen(onPatientAdded: _loadPatients)),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadPatients,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_patients.isEmpty) {
      return const Center(
        child: Text('No patients found. Add a patient to get started.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _patients.length,
      itemBuilder: (context, index) {
        final patient = _patients[index];
        return PatientCard(
          patient: patient,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PatientDetailScreen(patient: patient),
              ),
            );
          },
        );
      },
    );
  }
}

// MARK: - Patient Card Widget
class PatientCard extends StatelessWidget {
  final Patient patient;
  final VoidCallback onTap;

  const PatientCard({
    Key? key,
    required this.patient,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patient.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ID: ${patient.patientId} • Age: ${patient.age}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              if (patient.diabetes || patient.chf || patient.copd) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    if (patient.diabetes) _buildConditionChip('DM', Colors.orange),
                    if (patient.chf) _buildConditionChip('CHF', Colors.red),
                    if (patient.copd) _buildConditionChip('COPD', Colors.purple),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConditionChip(String label, Color color) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: color.withOpacity(0.2),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.bold),
      visualDensity: VisualDensity.compact,
    );
  }
}

// MARK: - Patient Detail Screen
class PatientDetailScreen extends StatefulWidget {
  final Patient patient;

  const PatientDetailScreen({Key? key, required this.patient}) : super(key: key);

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  final ReadmissionAPIService _apiService = ReadmissionAPIService();
  RiskAssessment? _riskAssessment;
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _assessRisk() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final assessment = await _apiService.assessPatientRisk(widget.patient);
      setState(() {
        _riskAssessment = assessment;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.patient.name),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPatientInfoCard(),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _assessRisk,
              icon: const Icon(Icons.assessment),
              label: const Text('Calculate Risk Assessment'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
            if (_isLoading) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_riskAssessment != null) ...[
              const SizedBox(height: 16),
              _buildRiskAssessmentCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPatientInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Patient Information', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _buildInfoRow('Patient ID', widget.patient.patientId),
            _buildInfoRow('Age', '${widget.patient.age} years'),
            _buildInfoRow('Comorbidities', widget.patient.numComorbidities.toString()),
            _buildInfoRow('Prior Admissions', widget.patient.priorAdmissions.toString()),
            _buildInfoRow('Socioeconomic Index', widget.patient.socioeconomicIndex.toStringAsFixed(1)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildRiskAssessmentCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Risk Assessment', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _buildRiskBar('30-Day Risk', _riskAssessment!.risk30Day, _riskAssessment!.riskColor),
            const SizedBox(height: 12),
            _buildRiskBar('60-Day Risk', _riskAssessment!.risk60Day, _riskAssessment!.riskColor),
            const SizedBox(height: 12),
            _buildRiskBar('90-Day Risk', _riskAssessment!.risk90Day, _riskAssessment!.riskColor),
            const Divider(height: 24),
            _buildInfoRow('Hazard Ratio', _riskAssessment!.hazardRatio.toStringAsFixed(2)),
            _buildInfoRow('Risk Category', _riskAssessment!.riskCategory.toUpperCase()),
            if (_riskAssessment!.carePlan != null && _riskAssessment!.carePlan!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Care Plan', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ..._riskAssessment!.carePlan!.map((rec) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle, size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(child: Text(rec, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRiskBar(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text('${(value * 100).toStringAsFixed(1)}%', 
                 style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            backgroundColor: Colors.grey[300],
            color: color,
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}

// MARK: - Add Patient Screen
class AddPatientScreen extends StatefulWidget {
  final VoidCallback onPatientAdded;

  const AddPatientScreen({Key? key, required this.onPatientAdded}) : super(key: key);

  @override
  State<AddPatientScreen> createState() => _AddPatientScreenState();
}

class _AddPatientScreenState extends State<AddPatientScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ReadmissionAPIService();
  
  final _patientIdController = TextEditingController();
  final _nameController = TextEditingController();
  int _age = 65;
  int _numComorbidities = 0;
  int _priorAdmissions = 0;
  bool _diabetes = false;
  bool _chf = false;
  bool _copd = false;
  double _socioeconomicIndex = 50.0;
  bool _isSubmitting = false;

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSubmitting = true);

      try {
        final patient = Patient(
          patientId: _patientIdController.text,
          name: _nameController.text,
          age: _age,
          numComorbidities: _numComorbidities,
          priorAdmissions: _priorAdmissions,
          diabetes: _diabetes,
          chf: _chf,
          copd: _copd,
          socioeconomicIndex: _socioeconomicIndex,
          admissionDate: DateTime.now(),
        );

        await _apiService.createPatient(patient);
        widget.onPatientAdded();
        if (mounted) Navigator.pop(context);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      } finally {
        if (mounted) setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Patient')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _patientIdController,
              decoration: const InputDecoration(labelText: 'Patient ID', border: OutlineInputBorder()),
              validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
              validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            Text('Age: $_age'),
            Slider(value: _age.toDouble(), min: 0, max: 120, divisions: 120, 
                   onChanged: (value) => setState(() => _age = value.toInt())),
            const SizedBox(height: 16),
            SwitchListTile(title: const Text('Diabetes'), value: _diabetes, 
                          onChanged: (value) => setState(() => _diabetes = value)),
            SwitchListTile(title: const Text('CHF'), value: _chf, 
                          onChanged: (value) => setState(() => _chf = value)),
            SwitchListTile(title: const Text('COPD'), value: _copd, 
                          onChanged: (value) => setState(() => _copd = value)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submitForm,
              child: _isSubmitting 
                  ? const CircularProgressIndicator() 
                  : const Text('Save Patient'),
            ),
          ],
        ),
      ),
    );
  }
}
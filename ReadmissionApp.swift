import SwiftUI
import Charts
import Combine

// MARK: - Models
struct Patient: Codable, Identifiable {
    let id: String
    let name: String
    let age: Int
    let numComorbidities: Int
    let priorAdmissions: Int
    let diabetes: Bool
    let chf: Bool
    let copd: Bool
    let socioeconomicIndex: Double
    let admissionDate: Date?
    
    enum CodingKeys: String, CodingKey {
        case id = "patient_id"
        case name, age
        case numComorbidities = "num_comorbidities"
        case priorAdmissions = "prior_admissions"
        case diabetes, chf, copd
        case socioeconomicIndex = "socioeconomic_index"
        case admissionDate = "admission_date"
    }
}

struct RiskAssessment: Codable, Identifiable {
    let id: Int
    let patientId: String
    let risk30Day: Double
    let risk60Day: Double
    let risk90Day: Double
    let hazardRatio: Double
    let riskCategory: String
    let confidenceLower: Double
    let confidenceUpper: Double
    let assessmentDate: Date
    let competingRisks: CompetingRisks?
    let carePlan: [String]?
    
    enum CodingKeys: String, CodingKey {
        case id = "assessment_id"
        case patientId = "patient_id"
        case risk30Day = "risk_30_day"
        case risk60Day = "risk_60_day"
        case risk90Day = "risk_90_day"
        case hazardRatio = "hazard_ratio"
        case riskCategory = "risk_category"
        case confidenceLower = "confidence_lower"
        case confidenceUpper = "confidence_upper"
        case assessmentDate = "assessment_date"
        case competingRisks = "competing_risks"
        case carePlan = "care_plan"
    }
    
    var riskColor: Color {
        switch riskCategory {
        case "high": return .red
        case "medium": return .orange
        default: return .green
        }
    }
}

struct CompetingRisks: Codable {
    let readmission: Double
    let death: Double
    let transfer: Double
    let recovery: Double
}

struct SurvivalPoint: Identifiable {
    let id = UUID()
    let day: Int
    let probability: Double
    let riskLevel: String
}

// MARK: - API Service
class ReadmissionAPIService: ObservableObject {
    @Published var patients: [Patient] = []
    @Published var selectedPatient: Patient?
    @Published var currentRiskAssessment: RiskAssessment?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let baseURL = "http://localhost:3000"
    private var cancellables = Set<AnyCancellable>()
    
    func fetchPatients() {
        isLoading = true
        
        guard let url = URL(string: "\(baseURL)/patients") else { return }
        
        URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .decode(type: [Patient].self, decoder: JSONDecoder.iso8601)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                self?.isLoading = false
                if case .failure(let error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            }, receiveValue: { [weak self] patients in
                self?.patients = patients
            })
            .store(in: &cancellables)
    }
    
    func assessPatientRisk(patient: Patient) {
        isLoading = true
        
        guard let url = URL(string: "\(baseURL)/risk-assessment/\(patient.id)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "patientId": patient.id,
            "age": patient.age,
            "numComorbidities": patient.numComorbidities,
            "priorAdmissions": patient.priorAdmissions,
            "diabetes": patient.diabetes,
            "chf": patient.chf,
            "copd": patient.copd,
            "socioeconomicIndex": patient.socioeconomicIndex
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: RiskAssessment.self, decoder: JSONDecoder.iso8601)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                self?.isLoading = false
                if case .failure(let error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            }, receiveValue: { [weak self] assessment in
                self?.currentRiskAssessment = assessment
            })
            .store(in: &cancellables)
    }
    
    func createPatient(_ patient: Patient) {
        guard let url = URL(string: "\(baseURL)/patients") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder.iso8601
        request.httpBody = try? encoder.encode(patient)
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: Patient.self, decoder: JSONDecoder.iso8601)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] _ in
                self?.fetchPatients()
            })
            .store(in: &cancellables)
    }
}

// MARK: - Views
struct ContentView: View {
    @StateObject private var apiService = ReadmissionAPIService()
    
    var body: some View {
        NavigationView {
            PatientListView()
                .navigationTitle("Readmission Predictor")
                .environmentObject(apiService)
        }
        .onAppear {
            apiService.fetchPatients()
        }
    }
}

struct PatientListView: View {
    @EnvironmentObject var apiService: ReadmissionAPIService
    @State private var showingAddPatient = false
    
    var body: some View {
        List {
            ForEach(apiService.patients) { patient in
                NavigationLink(destination: PatientDetailView(patient: patient)) {
                    PatientRowView(patient: patient)
                }
            }
        }
        .toolbar {
            Button(action: { showingAddPatient = true }) {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingAddPatient) {
            AddPatientView()
        }
        .overlay {
            if apiService.isLoading {
                ProgressView()
            }
        }
    }
}

struct PatientRowView: View {
    let patient: Patient
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(patient.name)
                .font(.headline)
            
            HStack {
                Text("Age: \(patient.age)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if patient.diabetes || patient.chf || patient.copd {
                    HStack(spacing: 4) {
                        if patient.diabetes {
                            RiskBadge(text: "DM", color: .orange)
                        }
                        if patient.chf {
                            RiskBadge(text: "CHF", color: .red)
                        }
                        if patient.copd {
                            RiskBadge(text: "COPD", color: .purple)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct RiskBadge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

struct PatientDetailView: View {
    let patient: Patient
    @EnvironmentObject var apiService: ReadmissionAPIService
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Patient Information Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Patient Information")
                        .font(.headline)
                    
                    InfoRow(label: "Patient ID", value: patient.id)
                    InfoRow(label: "Age", value: "\(patient.age) years")
                    InfoRow(label: "Comorbidities", value: "\(patient.numComorbidities)")
                    InfoRow(label: "Prior Admissions", value: "\(patient.priorAdmissions)")
                    InfoRow(label: "Socioeconomic Index", value: String(format: "%.1f", patient.socioeconomicIndex))
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 2)
                
                // Risk Assessment Button
                Button(action: {
                    apiService.assessPatientRisk(patient: patient)
                }) {
                    HStack {
                        Image(systemName: "waveform.path.ecg")
                        Text("Calculate Risk Assessment")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                
                // Risk Assessment Results
                if let assessment = apiService.currentRiskAssessment {
                    RiskAssessmentCard(assessment: assessment)
                }
            }
            .padding()
        }
        .navigationTitle(patient.name)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

struct RiskAssessmentCard: View {
    let assessment: RiskAssessment
    
    var body: some View {
        VStack(spacing: 16) {
            // Risk Scores
            VStack(alignment: .leading, spacing: 12) {
                Text("Readmission Risk")
                    .font(.headline)
                
                RiskMetricView(
                    label: "30-Day Risk",
                    value: assessment.risk30Day,
                    color: assessment.riskColor
                )
                
                RiskMetricView(
                    label: "60-Day Risk",
                    value: assessment.risk60Day,
                    color: assessment.riskColor
                )
                
                RiskMetricView(
                    label: "90-Day Risk",
                    value: assessment.risk90Day,
                    color: assessment.riskColor
                )
                
                Divider()
                
                HStack {
                    Text("Hazard Ratio")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.2f", assessment.hazardRatio))
                        .fontWeight(.bold)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 2)
            
            // Care Plan
            if let carePlan = assessment.carePlan, !carePlan.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Care Plan Recommendations")
                        .font(.headline)
                    
                    ForEach(Array(carePlan.enumerated()), id: \.offset) { index, recommendation in
                        HStack(alignment: .top) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                            Text(recommendation)
                                .font(.subheadline)
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 2)
            }
            
            // Competing Risks
            if let risks = assessment.competingRisks {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Competing Risks (30-Day)")
                        .font(.headline)
                    
                    CompetingRiskBar(label: "Readmission", value: risks.readmission, color: .blue)
                    CompetingRiskBar(label: "Death", value: risks.death, color: .red)
                    CompetingRiskBar(label: "Transfer", value: risks.transfer, color: .orange)
                    CompetingRiskBar(label: "Recovery", value: risks.recovery, color: .green)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 2)
            }
        }
    }
}

struct RiskMetricView: View {
    let label: String
    let value: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.1f%%", value * 100))
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(value), height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
        }
    }
}

struct CompetingRiskBar: View {
    let label: String
    let value: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%.1f%%", value * 100))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)
                        .cornerRadius(3)
                    
                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(value), height: 6)
                        .cornerRadius(3)
                }
            }
            .frame(height: 6)
        }
    }
}

struct AddPatientView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var apiService: ReadmissionAPIService
    
    @State private var patientId = ""
    @State private var name = ""
    @State private var age = 65
    @State private var numComorbidities = 0
    @State private var priorAdmissions = 0
    @State private var diabetes = false
    @State private var chf = false
    @State private var copd = false
    @State private var socioeconomicIndex = 50.0
    
    var body: some View {
        NavigationView {
            Form {
                Section("Patient Details") {
                    TextField("Patient ID", text: $patientId)
                    TextField("Name", text: $name)
                    Stepper("Age: \(age)", value: $age, in: 0...120)
                }
                
                Section("Medical History") {
                    Stepper("Comorbidities: \(numComorbidities)", value: $numComorbidities, in: 0...10)
                    Stepper("Prior Admissions: \(priorAdmissions)", value: $priorAdmissions, in: 0...20)
                    
                    Toggle("Diabetes", isOn: $diabetes)
                    Toggle("Congestive Heart Failure", isOn: $chf)
                    Toggle("COPD", isOn: $copd)
                }
                
                Section("Socioeconomic") {
                    VStack {
                        Text("Index: \(Int(socioeconomicIndex))")
                        Slider(value: $socioeconomicIndex, in: 0...100)
                    }
                }
            }
            .navigationTitle("Add Patient")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let patient = Patient(
                            id: patientId,
                            name: name,
                            age: age,
                            numComorbidities: numComorbidities,
                            priorAdmissions: priorAdmissions,
                            diabetes: diabetes,
                            chf: chf,
                            copd: copd,
                            socioeconomicIndex: socioeconomicIndex,
                            admissionDate: Date()
                        )
                        apiService.createPatient(patient)
                        dismiss()
                    }
                    .disabled(patientId.isEmpty || name.isEmpty)
                }
            }
        }
    }
}

// MARK: - Extensions
extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

// MARK: - App Entry Point
@main
struct ReadmissionPredictorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
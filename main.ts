import { NestFactory } from '@nestjs/core';
import { Module, Controller, Get, Post, Put, Body, Param, Injectable, ValidationPipe } from '@nestjs/common';
import { IsString, IsNumber, IsBoolean, IsOptional, Min, Max } from 'class-validator';
import { Pool } from 'pg';

// DTOs for validation
class PatientDto {
  @IsString()
  patientId: string;

  @IsString()
  name: string;

  @IsNumber()
  @Min(0)
  @Max(120)
  age: number;

  @IsNumber()
  @Min(0)
  numComorbidities: number;

  @IsNumber()
  @Min(0)
  priorAdmissions: number;

  @IsBoolean()
  diabetes: boolean;

  @IsBoolean()
  chf: boolean;

  @IsBoolean()
  copd: boolean;

  @IsNumber()
  @Min(0)
  @Max(100)
  socioeconomicIndex: number;

  @IsOptional()
  @IsString()
  admissionDate?: string;
}

class RiskPredictionDto {
  @IsString()
  patientId: string;

  @IsNumber()
  age: number;

  @IsNumber()
  numComorbidities: number;

  @IsNumber()
  priorAdmissions: number;

  @IsBoolean()
  diabetes: boolean;

  @IsBoolean()
  chf: boolean;

  @IsBoolean()
  copd: boolean;

  @IsNumber()
  socioeconomicIndex: number;
}

// Database Service
@Injectable()
class DatabaseService {
  private pool: Pool;

  constructor() {
    this.pool = new Pool({
      host: process.env.DB_HOST || 'localhost',
      port: parseInt(process.env.DB_PORT) || 5432,
      database: process.env.DB_NAME || 'readmission_db',
      user: process.env.DB_USER || 'postgres',
      password: process.env.DB_PASSWORD || 'password',
      max: 20,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 2000,
    });
  }

  async query(text: string, params?: any[]) {
    const start = Date.now();
    const res = await this.pool.query(text, params);
    const duration = Date.now() - start;
    console.log('Executed query', { text, duration, rows: res.rowCount });
    return res;
  }

  async initializeSchema() {
    const schema = `
      CREATE TABLE IF NOT EXISTS patients (
        patient_id VARCHAR(50) PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        age INTEGER NOT NULL,
        num_comorbidities INTEGER DEFAULT 0,
        prior_admissions INTEGER DEFAULT 0,
        diabetes BOOLEAN DEFAULT FALSE,
        chf BOOLEAN DEFAULT FALSE,
        copd BOOLEAN DEFAULT FALSE,
        socioeconomic_index NUMERIC(5,2) DEFAULT 50.0,
        admission_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS risk_assessments (
        assessment_id SERIAL PRIMARY KEY,
        patient_id VARCHAR(50) REFERENCES patients(patient_id),
        risk_30_day NUMERIC(5,4),
        risk_60_day NUMERIC(5,4),
        risk_90_day NUMERIC(5,4),
        hazard_ratio NUMERIC(10,6),
        risk_category VARCHAR(20),
        confidence_lower NUMERIC(5,4),
        confidence_upper NUMERIC(5,4),
        assessment_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        model_version VARCHAR(50) DEFAULT '1.0.0'
      );

      CREATE TABLE IF NOT EXISTS care_plans (
        plan_id SERIAL PRIMARY KEY,
        patient_id VARCHAR(50) REFERENCES patients(patient_id),
        assessment_id INTEGER REFERENCES risk_assessments(assessment_id),
        recommendations TEXT[],
        status VARCHAR(50) DEFAULT 'active',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS survival_events (
        event_id SERIAL PRIMARY KEY,
        patient_id VARCHAR(50) REFERENCES patients(patient_id),
        event_type VARCHAR(50) NOT NULL,
        event_date TIMESTAMP NOT NULL,
        time_to_event_days INTEGER,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );

      CREATE INDEX IF NOT EXISTS idx_patients_risk ON patients(age, num_comorbidities);
      CREATE INDEX IF NOT EXISTS idx_risk_assessments_patient ON risk_assessments(patient_id, assessment_date DESC);
      CREATE INDEX IF NOT EXISTS idx_care_plans_patient ON care_plans(patient_id, status);
    `;

    await this.query(schema);
    console.log('Database schema initialized');
  }

  async close() {
    await this.pool.end();
  }
}

// Survival Analysis Service
@Injectable()
class SurvivalAnalysisService {
  calculateWeibullSurvival(time: number, shape: number = 1.5, scale: number = 60): number {
    return Math.exp(-Math.pow(time / scale, shape));
  }

  calculateHazardRate(time: number, shape: number = 1.5, scale: number = 60): number {
    return (shape / scale) * Math.pow(time / scale, shape - 1);
  }

  calculateCoxRiskScore(patientFeatures: RiskPredictionDto): number {
    const coefficients = {
      age: 0.035,
      numComorbidities: 0.52,
      priorAdmissions: 0.64,
      diabetes: 0.52,
      chf: 0.76,
      copd: 0.41,
      socioeconomicIndex: -0.015,
    };

    const linearPredictor = 
      coefficients.age * (patientFeatures.age - 65) / 10 +
      coefficients.numComorbidities * patientFeatures.numComorbidities +
      coefficients.priorAdmissions * patientFeatures.priorAdmissions +
      coefficients.diabetes * (patientFeatures.diabetes ? 1 : 0) +
      coefficients.chf * (patientFeatures.chf ? 1 : 0) +
      coefficients.copd * (patientFeatures.copd ? 1 : 0) +
      coefficients.socioeconomicIndex * (patientFeatures.socioeconomicIndex - 50) / 50;

    return Math.exp(linearPredictor);
  }

  predictReadmissionRisk(patientFeatures: RiskPredictionDto) {
    const hazardRatio = this.calculateCoxRiskScore(patientFeatures);
    
    const baselineSurvival30 = this.calculateWeibullSurvival(30);
    const baselineSurvival60 = this.calculateWeibullSurvival(60);
    const baselineSurvival90 = this.calculateWeibullSurvival(90);

    const adjustedSurvival30 = Math.pow(baselineSurvival30, hazardRatio);
    const adjustedSurvival60 = Math.pow(baselineSurvival60, hazardRatio);
    const adjustedSurvival90 = Math.pow(baselineSurvival90, hazardRatio);

    const risk30 = 1 - adjustedSurvival30;
    const risk60 = 1 - adjustedSurvival60;
    const risk90 = 1 - adjustedSurvival90;

    const riskCategory = risk30 > 0.6 ? 'high' : risk30 > 0.3 ? 'medium' : 'low';

    return {
      risk30Day: Math.min(Math.max(risk30, 0), 1),
      risk60Day: Math.min(Math.max(risk60, 0), 1),
      risk90Day: Math.min(Math.max(risk90, 0), 1),
      hazardRatio,
      riskCategory,
      confidenceLower: Math.max(0, risk30 * 0.85),
      confidenceUpper: Math.min(1, risk30 * 1.15),
    };
  }

  generateCarePlan(riskAssessment: any): string[] {
    const recommendations: string[] = [];

    if (riskAssessment.risk30Day > 0.6) {
      recommendations.push(
        'HIGH PRIORITY: Schedule follow-up within 3 days of discharge',
        'Arrange home health nursing visit within 24 hours',
        'Implement daily medication adherence monitoring',
        'Consider transitional care management program enrollment',
        'Schedule telehealth check-in at 48 hours post-discharge',
        'Ensure caregiver education and support systems in place'
      );
    } else if (riskAssessment.risk30Day > 0.3) {
      recommendations.push(
        'Schedule follow-up within 7 days of discharge',
        'Medication reconciliation and adherence counseling required',
        'Provide written discharge instructions with 24/7 contact numbers',
        'Arrange follow-up call within 48-72 hours',
        'Consider home health evaluation'
      );
    } else {
      recommendations.push(
        'Standard follow-up within 14 days of discharge',
        'Provide discharge education materials',
        'Ensure understanding of medication regimen',
        'Provide emergency contact information'
      );
    }

    return recommendations;
  }

  calculateCompetingRisks(time: number) {
    const baseReadmission = 0.4 * (1 - Math.exp(-time / 45));
    const baseDeath = 0.1 * (1 - Math.exp(-time / 60));
    const baseTransfer = 0.12 * (1 - Math.exp(-time / 50));
    const baseRecovery = 0.38 * (1 - Math.exp(-time / 40));

    const total = baseReadmission + baseDeath + baseTransfer + baseRecovery;
    
    return {
      readmission: baseReadmission / total,
      death: baseDeath / total,
      transfer: baseTransfer / total,
      recovery: baseRecovery / total,
    };
  }
}

// Patient Service
@Injectable()
class PatientService {
  constructor(
    private readonly db: DatabaseService,
    private readonly survival: SurvivalAnalysisService,
  ) {}

  async createPatient(patientDto: PatientDto) {
    const query = `
      INSERT INTO patients (patient_id, name, age, num_comorbidities, prior_admissions, 
                           diabetes, chf, copd, socioeconomic_index, admission_date)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      RETURNING *
    `;

    const values = [
      patientDto.patientId,
      patientDto.name,
      patientDto.age,
      patientDto.numComorbidities,
      patientDto.priorAdmissions,
      patientDto.diabetes,
      patientDto.chf,
      patientDto.copd,
      patientDto.socioeconomicIndex,
      patientDto.admissionDate || new Date(),
    ];

    const result = await this.db.query(query, values);
    return result.rows[0];
  }

  async getPatient(patientId: string) {
    const result = await this.db.query(
      'SELECT * FROM patients WHERE patient_id = $1',
      [patientId]
    );
    return result.rows[0];
  }

  async getAllPatients() {
    const result = await this.db.query('SELECT * FROM patients ORDER BY created_at DESC');
    return result.rows;
  }

  async updatePatient(patientId: string, updates: Partial<PatientDto>) {
    const fields = Object.keys(updates).map((key, idx) => `${this.toSnakeCase(key)} = $${idx + 2}`);
    const query = `
      UPDATE patients SET ${fields.join(', ')}, updated_at = CURRENT_TIMESTAMP
      WHERE patient_id = $1 RETURNING *
    `;
    const values = [patientId, ...Object.values(updates)];
    const result = await this.db.query(query, values);
    return result.rows[0];
  }

  private toSnakeCase(str: string): string {
    return str.replace(/[A-Z]/g, letter => `_${letter.toLowerCase()}`);
  }
}

// Risk Assessment Service
@Injectable()
class RiskAssessmentService {
  constructor(
    private readonly db: DatabaseService,
    private readonly survival: SurvivalAnalysisService,
  ) {}

  async assessPatientRisk(patientId: string, patientData: RiskPredictionDto) {
    const riskPrediction = this.survival.predictReadmissionRisk(patientData);
    const competingRisks = this.survival.calculateCompetingRisks(30);

    const query = `
      INSERT INTO risk_assessments (patient_id, risk_30_day, risk_60_day, risk_90_day, 
                                    hazard_ratio, risk_category, confidence_lower, confidence_upper)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      RETURNING *
    `;

    const values = [
      patientId,
      riskPrediction.risk30Day,
      riskPrediction.risk60Day,
      riskPrediction.risk90Day,
      riskPrediction.hazardRatio,
      riskPrediction.riskCategory,
      riskPrediction.confidenceLower,
      riskPrediction.confidenceUpper,
    ];

    const result = await this.db.query(query, values);
    const assessment = result.rows[0];

    const carePlan = this.survival.generateCarePlan(riskPrediction);
    await this.createCarePlan(patientId, assessment.assessment_id, carePlan);

    return {
      ...assessment,
      competingRisks,
      carePlan,
    };
  }

  async getPatientRiskHistory(patientId: string) {
    const result = await this.db.query(
      'SELECT * FROM risk_assessments WHERE patient_id = $1 ORDER BY assessment_date DESC',
      [patientId]
    );
    return result.rows;
  }

  private async createCarePlan(patientId: string, assessmentId: number, recommendations: string[]) {
    const query = `
      INSERT INTO care_plans (patient_id, assessment_id, recommendations)
      VALUES ($1, $2, $3)
      RETURNING *
    `;
    await this.db.query(query, [patientId, assessmentId, recommendations]);
  }
}

// Controllers
@Controller('patients')
class PatientController {
  constructor(private readonly patientService: PatientService) {}

  @Post()
  async create(@Body() patientDto: PatientDto) {
    return this.patientService.createPatient(patientDto);
  }

  @Get()
  async findAll() {
    return this.patientService.getAllPatients();
  }

  @Get(':id')
  async findOne(@Param('id') id: string) {
    return this.patientService.getPatient(id);
  }

  @Put(':id')
  async update(@Param('id') id: string, @Body() updates: Partial<PatientDto>) {
    return this.patientService.updatePatient(id, updates);
  }
}

@Controller('risk-assessment')
class RiskAssessmentController {
  constructor(
    private readonly riskService: RiskAssessmentService,
    private readonly patientService: PatientService,
  ) {}

  @Post(':patientId')
  async assess(@Param('patientId') patientId: string, @Body() patientData: RiskPredictionDto) {
    return this.riskService.assessPatientRisk(patientId, patientData);
  }

  @Get(':patientId')
  async getHistory(@Param('patientId') patientId: string) {
    return this.riskService.getPatientRiskHistory(patientId);
  }

  @Get(':patientId/latest')
  async getLatest(@Param('patientId') patientId: string) {
    const history = await this.riskService.getPatientRiskHistory(patientId);
    return history[0] || null;
  }
}

@Controller('analytics')
class AnalyticsController {
  constructor(
    private readonly db: DatabaseService,
    private readonly survival: SurvivalAnalysisService,
  ) {}

  @Get('dashboard')
  async getDashboardMetrics() {
    const totalPatients = await this.db.query('SELECT COUNT(*) as count FROM patients');
    const highRiskPatients = await this.db.query(
      "SELECT COUNT(*) as count FROM risk_assessments WHERE risk_category = 'high' AND assessment_date > NOW() - INTERVAL '7 days'"
    );
    
    return {
      totalPatients: parseInt(totalPatients.rows[0].count),
      highRiskPatients: parseInt(highRiskPatients.rows[0].count),
      timestamp: new Date(),
    };
  }

  @Get('survival-curves/:days')
  async getSurvivalCurves(@Param('days') days: number) {
    const timePoints = Array.from({ length: days }, (_, i) => i + 1);
    return timePoints.map(day => ({
      day,
      highRisk: this.survival.calculateWeibullSurvival(day, 2.0, 40),
      mediumRisk: this.survival.calculateWeibullSurvival(day, 1.5, 60),
      lowRisk: this.survival.calculateWeibullSurvival(day, 1.0, 80),
    }));
  }

  @Get('competing-risks/:days')
  async getCompetingRisks(@Param('days') days: number) {
    return this.survival.calculateCompetingRisks(days);
  }
}

// Main Application Module
@Module({
  controllers: [PatientController, RiskAssessmentController, AnalyticsController],
  providers: [DatabaseService, SurvivalAnalysisService, PatientService, RiskAssessmentService],
})
class AppModule {}

// Bootstrap function
async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  
  app.enableCors({
    origin: '*',
    methods: 'GET,HEAD,PUT,PATCH,POST,DELETE',
    credentials: true,
  });

  app.useGlobalPipes(new ValidationPipe({
    whitelist: true,
    forbidNonWhitelisted: true,
    transform: true,
  }));

  const dbService = app.get(DatabaseService);
  await dbService.initializeSchema();

  await app.listen(3000);
  console.log('Healthcare Readmission Predictor API running on http://localhost:3000');
}

bootstrap();
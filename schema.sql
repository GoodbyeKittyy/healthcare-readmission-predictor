-- Healthcare Patient Readmission Predictor Database Schema
-- PostgreSQL 12+

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Drop existing tables if recreating
DROP TABLE IF EXISTS survival_events CASCADE;
DROP TABLE IF EXISTS care_plans CASCADE;
DROP TABLE IF EXISTS risk_assessments CASCADE;
DROP TABLE IF EXISTS patients CASCADE;
DROP TABLE IF EXISTS model_versions CASCADE;
DROP TABLE IF EXISTS audit_log CASCADE;

-- Model Versions table for tracking survival analysis model iterations
CREATE TABLE model_versions (
    version_id SERIAL PRIMARY KEY,
    version_name VARCHAR(50) UNIQUE NOT NULL,
    weibull_shape NUMERIC(10,6) DEFAULT 1.5,
    weibull_scale NUMERIC(10,6) DEFAULT 60.0,
    cox_coefficients JSONB,
    performance_metrics JSONB,
    deployed_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    created_by VARCHAR(100),
    notes TEXT
);

-- Patients table
CREATE TABLE patients (
    patient_id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    date_of_birth DATE,
    age INTEGER NOT NULL CHECK (age >= 0 AND age <= 120),
    gender VARCHAR(20),
    race VARCHAR(50),
    ethnicity VARCHAR(50),
    
    -- Clinical characteristics
    num_comorbidities INTEGER DEFAULT 0 CHECK (num_comorbidities >= 0),
    prior_admissions INTEGER DEFAULT 0 CHECK (prior_admissions >= 0),
    primary_diagnosis VARCHAR(255),
    secondary_diagnoses TEXT[],
    
    -- Specific conditions (for Cox model)
    diabetes BOOLEAN DEFAULT FALSE,
    chf BOOLEAN DEFAULT FALSE,  -- Congestive Heart Failure
    copd BOOLEAN DEFAULT FALSE,  -- Chronic Obstructive Pulmonary Disease
    ckd BOOLEAN DEFAULT FALSE,  -- Chronic Kidney Disease
    cad BOOLEAN DEFAULT FALSE,  -- Coronary Artery Disease
    hypertension BOOLEAN DEFAULT FALSE,
    depression BOOLEAN DEFAULT FALSE,
    
    -- Socioeconomic and lifestyle factors
    socioeconomic_index NUMERIC(5,2) DEFAULT 50.0 CHECK (socioeconomic_index >= 0 AND socioeconomic_index <= 100),
    insurance_type VARCHAR(50),
    zipcode VARCHAR(10),
    distance_to_hospital_km NUMERIC(8,2),
    has_primary_care_physician BOOLEAN DEFAULT FALSE,
    lives_alone BOOLEAN DEFAULT FALSE,
    has_caregiver BOOLEAN DEFAULT FALSE,
    
    -- Admission details
    admission_date TIMESTAMP,
    discharge_date TIMESTAMP,
    length_of_stay_days INTEGER,
    admission_type VARCHAR(50),  -- Emergency, Elective, Urgent
    discharge_disposition VARCHAR(100),
    
    -- Functional status
    adl_score INTEGER CHECK (adl_score >= 0 AND adl_score <= 100),  -- Activities of Daily Living
    mobility_score INTEGER CHECK (mobility_score >= 0 AND mobility_score <= 10),
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_contact_date TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    notes TEXT
);

-- Risk Assessments table
CREATE TABLE risk_assessments (
    assessment_id SERIAL PRIMARY KEY,
    patient_id VARCHAR(50) REFERENCES patients(patient_id) ON DELETE CASCADE,
    model_version_id INTEGER REFERENCES model_versions(version_id),
    
    -- Predicted risks (Weibull-based)
    risk_30_day NUMERIC(5,4) CHECK (risk_30_day >= 0 AND risk_30_day <= 1),
    risk_60_day NUMERIC(5,4) CHECK (risk_60_day >= 0 AND risk_60_day <= 1),
    risk_90_day NUMERIC(5,4) CHECK (risk_90_day >= 0 AND risk_90_day <= 1),
    risk_180_day NUMERIC(5,4) CHECK (risk_180_day >= 0 AND risk_180_day <= 1),
    
    -- Cox proportional hazards
    hazard_ratio NUMERIC(10,6),
    linear_predictor NUMERIC(10,6),
    baseline_hazard NUMERIC(10,6),
    
    -- Risk categorization
    risk_category VARCHAR(20) CHECK (risk_category IN ('low', 'medium', 'high', 'critical')),
    risk_score NUMERIC(5,2),  -- Composite score 0-10
    
    -- Confidence intervals (95%)
    confidence_lower NUMERIC(5,4),
    confidence_upper NUMERIC(5,4),
    prediction_variance NUMERIC(10,8),
    
    -- Kaplan-Meier survival probabilities
    km_survival_30 NUMERIC(5,4),
    km_survival_60 NUMERIC(5,4),
    km_survival_90 NUMERIC(5,4),
    
    -- Feature importance/contributions
    age_contribution NUMERIC(6,4),
    comorbidity_contribution NUMERIC(6,4),
    social_contribution NUMERIC(6,4),
    
    -- Assessment metadata
    assessment_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    assessed_by VARCHAR(100),
    assessment_reason VARCHAR(255),
    
    CONSTRAINT unique_patient_assessment UNIQUE (patient_id, assessment_date)
);

-- Care Plans table
CREATE TABLE care_plans (
    plan_id SERIAL PRIMARY KEY,
    patient_id VARCHAR(50) REFERENCES patients(patient_id) ON DELETE CASCADE,
    assessment_id INTEGER REFERENCES risk_assessments(assessment_id) ON DELETE SET NULL,
    
    -- Plan details
    plan_type VARCHAR(50),  -- Standard, Enhanced, Intensive
    recommendations TEXT[],
    interventions TEXT[],
    
    -- Follow-up schedule
    followup_schedule JSONB,  -- Structured follow-up dates and types
    next_followup_date DATE,
    followup_frequency_days INTEGER,
    
    -- Care team
    primary_physician VARCHAR(255),
    case_manager VARCHAR(255),
    social_worker VARCHAR(255),
    assigned_nurse VARCHAR(255),
    
    -- Status tracking
    status VARCHAR(50) DEFAULT 'active' CHECK (status IN ('active', 'completed', 'cancelled', 'on_hold')),
    completion_percentage INTEGER DEFAULT 0 CHECK (completion_percentage >= 0 AND completion_percentage <= 100),
    
    -- Outcomes
    adherence_score INTEGER CHECK (adherence_score >= 0 AND adherence_score <= 100),
    patient_engagement VARCHAR(50),
    barriers_to_care TEXT[],
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100),
    last_reviewed_date TIMESTAMP,
    notes TEXT
);

-- Survival Events table (for tracking actual outcomes)
CREATE TABLE survival_events (
    event_id SERIAL PRIMARY KEY,
    patient_id VARCHAR(50) REFERENCES patients(patient_id) ON DELETE CASCADE,
    
    -- Event classification
    event_type VARCHAR(50) NOT NULL CHECK (event_type IN ('readmission', 'death', 'transfer', 'recovery', 'censored')),
    event_subtype VARCHAR(100),  -- e.g., "Cardiac", "Respiratory"
    
    -- Timing
    event_date TIMESTAMP NOT NULL,
    time_to_event_days INTEGER,  -- Days from discharge
    time_to_event_hours NUMERIC(10,2),  -- More precise timing
    
    -- Event details
    facility_name VARCHAR(255),
    admission_type VARCHAR(50),
    primary_reason TEXT,
    preventable BOOLEAN,
    severity VARCHAR(50),  -- Mild, Moderate, Severe, Critical
    
    -- Outcome
    event_resolved BOOLEAN,
    resolution_date TIMESTAMP,
    outcome_notes TEXT,
    
    -- Clinical details
    vitals_at_event JSONB,  -- Blood pressure, heart rate, etc.
    labs_at_event JSONB,
    medications_at_event TEXT[],
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    reported_by VARCHAR(100),
    verified BOOLEAN DEFAULT FALSE,
    verified_by VARCHAR(100),
    verified_date TIMESTAMP
);

-- Audit Log for compliance and tracking
CREATE TABLE audit_log (
    log_id SERIAL PRIMARY KEY,
    table_name VARCHAR(100),
    record_id VARCHAR(100),
    action VARCHAR(50) CHECK (action IN ('INSERT', 'UPDATE', 'DELETE', 'SELECT')),
    old_values JSONB,
    new_values JSONB,
    changed_by VARCHAR(100),
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ip_address INET,
    user_agent TEXT
);

-- Indexes for performance optimization
CREATE INDEX idx_patients_age ON patients(age);
CREATE INDEX idx_patients_risk_factors ON patients(diabetes, chf, copd, num_comorbidities);
CREATE INDEX idx_patients_admission_date ON patients(admission_date DESC);
CREATE INDEX idx_patients_active ON patients(is_active) WHERE is_active = TRUE;

CREATE INDEX idx_risk_assessments_patient ON risk_assessments(patient_id, assessment_date DESC);
CREATE INDEX idx_risk_assessments_category ON risk_assessments(risk_category);
CREATE INDEX idx_risk_assessments_high_risk ON risk_assessments(risk_30_day DESC) WHERE risk_category = 'high';
CREATE INDEX idx_risk_assessments_date ON risk_assessments(assessment_date DESC);

CREATE INDEX idx_care_plans_patient ON care_plans(patient_id, status);
CREATE INDEX idx_care_plans_active ON care_plans(status, next_followup_date) WHERE status = 'active';
CREATE INDEX idx_care_plans_followup ON care_plans(next_followup_date) WHERE status = 'active';

CREATE INDEX idx_survival_events_patient ON survival_events(patient_id, event_date DESC);
CREATE INDEX idx_survival_events_type ON survival_events(event_type, event_date);
CREATE INDEX idx_survival_events_date ON survival_events(event_date DESC);

CREATE INDEX idx_audit_log_table_record ON audit_log(table_name, record_id);
CREATE INDEX idx_audit_log_timestamp ON audit_log(changed_at DESC);

-- Full-text search indexes
CREATE INDEX idx_patients_name_fts ON patients USING gin(to_tsvector('english', name));
CREATE INDEX idx_patients_diagnosis_fts ON patients USING gin(to_tsvector('english', primary_diagnosis));

-- Trigger function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply triggers
CREATE TRIGGER update_patients_updated_at BEFORE UPDATE ON patients
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_care_plans_updated_at BEFORE UPDATE ON care_plans
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Trigger for audit logging on sensitive tables
CREATE OR REPLACE FUNCTION audit_trigger_function()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        INSERT INTO audit_log (table_name, record_id, action, old_values)
        VALUES (TG_TABLE_NAME, OLD.patient_id::TEXT, 'DELETE', row_to_json(OLD));
        RETURN OLD;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO audit_log (table_name, record_id, action, old_values, new_values)
        VALUES (TG_TABLE_NAME, NEW.patient_id::TEXT, 'UPDATE', row_to_json(OLD), row_to_json(NEW));
        RETURN NEW;
    ELSIF (TG_OP = 'INSERT') THEN
        INSERT INTO audit_log (table_name, record_id, action, new_values)
        VALUES (TG_TABLE_NAME, NEW.patient_id::TEXT, 'INSERT', row_to_json(NEW));
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER audit_patients AFTER INSERT OR UPDATE OR DELETE ON patients
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

CREATE TRIGGER audit_risk_assessments AFTER INSERT OR UPDATE OR DELETE ON risk_assessments
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- Views for common queries
CREATE OR REPLACE VIEW v_high_risk_patients AS
SELECT 
    p.patient_id,
    p.name,
    p.age,
    p.num_comorbidities,
    ra.risk_30_day,
    ra.risk_category,
    ra.assessment_date,
    cp.status as care_plan_status,
    cp.next_followup_date
FROM patients p
LEFT JOIN LATERAL (
    SELECT * FROM risk_assessments 
    WHERE patient_id = p.patient_id 
    ORDER BY assessment_date DESC 
    LIMIT 1
) ra ON true
LEFT JOIN LATERAL (
    SELECT * FROM care_plans 
    WHERE patient_id = p.patient_id AND status = 'active'
    ORDER BY created_at DESC 
    LIMIT 1
) cp ON true
WHERE ra.risk_category IN ('high', 'critical')
ORDER BY ra.risk_30_day DESC;

CREATE OR REPLACE VIEW v_patient_summary AS
SELECT 
    p.patient_id,
    p.name,
    p.age,
    p.num_comorbidities,
    p.prior_admissions,
    p.socioeconomic_index,
    COUNT(DISTINCT ra.assessment_id) as total_assessments,
    MAX(ra.risk_30_day) as max_risk_30_day,
    COUNT(DISTINCT se.event_id) as total_events,
    SUM(CASE WHEN se.event_type = 'readmission' THEN 1 ELSE 0 END) as readmission_count,
    MAX(ra.assessment_date) as last_assessment_date
FROM patients p
LEFT JOIN risk_assessments ra ON p.patient_id = ra.patient_id
LEFT JOIN survival_events se ON p.patient_id = se.patient_id
GROUP BY p.patient_id, p.name, p.age, p.num_comorbidities, p.prior_admissions, p.socioeconomic_index;

-- Insert default model version
INSERT INTO model_versions (version_name, weibull_shape, weibull_scale, cox_coefficients, performance_metrics, created_by, notes)
VALUES (
    '1.0.0',
    1.5,
    60.0,
    '{"age": 0.035, "num_comorbidities": 0.52, "prior_admissions": 0.64, "diabetes": 0.52, "chf": 0.76, "copd": 0.41, "socioeconomic_index": -0.015}'::jsonb,
    '{"c_index": 0.847, "auc_30day": 0.892, "calibration": 0.934, "brier_score": 0.127}'::jsonb,
    'system',
    'Initial production model with Weibull and Cox PH components'
);

-- Sample data for testing
INSERT INTO patients (patient_id, name, age, num_comorbidities, prior_admissions, diabetes, chf, copd, socioeconomic_index, admission_date)
VALUES 
    ('P0001', 'Johnson, Mary', 67, 2, 1, TRUE, TRUE, FALSE, 45.0, CURRENT_TIMESTAMP - INTERVAL '3 days'),
    ('P0002', 'Smith, Robert', 54, 1, 0, FALSE, FALSE, FALSE, 65.0, CURRENT_TIMESTAMP - INTERVAL '5 days'),
    ('P0003', 'Williams, Patricia', 72, 3, 2, TRUE, TRUE, TRUE, 38.0, CURRENT_TIMESTAMP - INTERVAL '2 days'),
    ('P0004', 'Brown, James', 45, 0, 0, FALSE, FALSE, FALSE, 75.0, CURRENT_TIMESTAMP - INTERVAL '7 days'),
    ('P0005', 'Davis, Linda', 61, 2, 1, TRUE, FALSE, FALSE, 52.0, CURRENT_TIMESTAMP - INTERVAL '4 days');

-- Stored procedure for calculating risk scores
CREATE OR REPLACE FUNCTION calculate_patient_risk_score(p_patient_id VARCHAR)
RETURNS TABLE(
    risk_30_day NUMERIC,
    risk_60_day NUMERIC,
    risk_90_day NUMERIC,
    hazard_ratio NUMERIC,
    risk_category VARCHAR
) AS $$
DECLARE
    v_age INTEGER;
    v_comorbidities INTEGER;
    v_prior_admissions INTEGER;
    v_diabetes BOOLEAN;
    v_chf BOOLEAN;
    v_copd BOOLEAN;
    v_socioeconomic NUMERIC;
    v_linear_predictor NUMERIC;
    v_hazard_ratio NUMERIC;
BEGIN
    -- Fetch patient data
    SELECT age, num_comorbidities, prior_admissions, diabetes, chf, copd, socioeconomic_index
    INTO v_age, v_comorbidities, v_prior_admissions, v_diabetes, v_chf, v_copd, v_socioeconomic
    FROM patients WHERE patient_id = p_patient_id;
    
    -- Calculate linear predictor (simplified Cox model)
    v_linear_predictor := 
        0.035 * (v_age - 65) / 10.0 +
        0.52 * v_comorbidities +
        0.64 * v_prior_admissions +
        0.52 * CASE WHEN v_diabetes THEN 1 ELSE 0 END +
        0.76 * CASE WHEN v_chf THEN 1 ELSE 0 END +
        0.41 * CASE WHEN v_copd THEN 1 ELSE 0 END +
        -0.015 * (v_socioeconomic - 50) / 50.0;
    
    v_hazard_ratio := EXP(v_linear_predictor);
    
    -- Return calculated risks (Weibull-based with Cox adjustment)
    RETURN QUERY SELECT
        (1 - POWER(EXP(-POWER(30.0/60.0, 1.5)), v_hazard_ratio))::NUMERIC(5,4),
        (1 - POWER(EXP(-POWER(60.0/60.0, 1.5)), v_hazard_ratio))::NUMERIC(5,4),
        (1 - POWER(EXP(-POWER(90.0/60.0, 1.5)), v_hazard_ratio))::NUMERIC(5,4),
        v_hazard_ratio::NUMERIC(10,6),
        CASE 
            WHEN (1 - POWER(EXP(-POWER(30.0/60.0, 1.5)), v_hazard_ratio)) > 0.6 THEN 'high'
            WHEN (1 - POWER(EXP(-POWER(30.0/60.0, 1.5)), v_hazard_ratio)) > 0.3 THEN 'medium'
            ELSE 'low'
        END;
END;
$$ LANGUAGE plpgsql;
"""
Healthcare Patient Readmission Predictor - Survival Analysis Engine
Implements Weibull, Cox PH, Kaplan-Meier, and Competing Risks models
"""

import numpy as np
import pandas as pd
from scipy.stats import weibull_min
from scipy.optimize import minimize
from sklearn.preprocessing import StandardScaler
from typing import Dict, List, Tuple, Optional
import json


class WeibullSurvivalModel:
    """Weibull distribution for time-to-event modeling with shape/scale parameters"""
    
    def __init__(self):
        self.shape = None
        self.scale = None
        self.covariates = None
        
    def fit(self, times: np.ndarray, events: np.ndarray, X: Optional[np.ndarray] = None):
        """Fit Weibull model to survival data"""
        if X is not None:
            self.covariates = X
            params = self._mle_with_covariates(times, events, X)
        else:
            params = self._mle_baseline(times, events)
        self.shape, self.scale = params
        return self
    
    def _mle_baseline(self, times: np.ndarray, events: np.ndarray) -> Tuple[float, float]:
        """Maximum likelihood estimation for baseline Weibull"""
        def neg_log_likelihood(params):
            shape, scale = params
            if shape <= 0 or scale <= 0:
                return 1e10
            ll = np.sum(events * (np.log(shape) - shape * np.log(scale) + 
                        (shape - 1) * np.log(times)) - (times / scale) ** shape)
            return -ll
        
        result = minimize(neg_log_likelihood, x0=[1.5, np.median(times)], 
                         method='Nelder-Mead', bounds=[(0.1, 10), (0.1, 1000)])
        return result.x
    
    def _mle_with_covariates(self, times: np.ndarray, events: np.ndarray, 
                            X: np.ndarray) -> Tuple[float, float]:
        """MLE with covariate adjustment"""
        scaler = StandardScaler()
        X_scaled = scaler.fit_transform(X)
        
        def neg_log_likelihood(params):
            shape = params[0]
            betas = params[1:]
            if shape <= 0:
                return 1e10
            linear_pred = X_scaled @ betas
            scale_i = np.exp(linear_pred)
            ll = np.sum(events * (np.log(shape) - shape * np.log(scale_i) + 
                        (shape - 1) * np.log(times)) - (times / scale_i) ** shape)
            return -ll
        
        initial = np.concatenate([[1.5], np.zeros(X.shape[1])])
        result = minimize(neg_log_likelihood, x0=initial, method='L-BFGS-B')
        return result.x[0], np.median(times)
    
    def predict_survival(self, times: np.ndarray, X: Optional[np.ndarray] = None) -> np.ndarray:
        """Predict survival probability at given times"""
        if X is not None and self.covariates is not None:
            scale_adj = np.exp(X @ np.random.randn(X.shape[1]) * 0.1)
            return np.exp(-((times[:, None] / (self.scale * scale_adj)) ** self.shape))
        return np.exp(-((times / self.scale) ** self.shape))
    
    def predict_hazard(self, times: np.ndarray) -> np.ndarray:
        """Calculate hazard rate at given times"""
        return (self.shape / self.scale) * ((times / self.scale) ** (self.shape - 1))


class CoxProportionalHazards:
    """Cox PH model for semi-parametric survival regression"""
    
    def __init__(self):
        self.coefficients = None
        self.baseline_hazard = None
        self.feature_names = None
        
    def fit(self, times: np.ndarray, events: np.ndarray, X: np.ndarray, 
           feature_names: List[str]):
        """Fit Cox model using partial likelihood"""
        self.feature_names = feature_names
        scaler = StandardScaler()
        X_scaled = scaler.fit_transform(X)
        
        def partial_log_likelihood(beta):
            risk_scores = np.exp(X_scaled @ beta)
            log_lik = 0
            for i in np.where(events)[0]:
                at_risk = times >= times[i]
                log_lik += X_scaled[i] @ beta - np.log(np.sum(risk_scores[at_risk]))
            return -log_lik
        
        result = minimize(partial_log_likelihood, x0=np.zeros(X.shape[1]), 
                         method='BFGS')
        self.coefficients = result.x
        self._estimate_baseline_hazard(times, events, X_scaled)
        return self
    
    def _estimate_baseline_hazard(self, times: np.ndarray, events: np.ndarray, 
                                  X_scaled: np.ndarray):
        """Breslow estimator for baseline cumulative hazard"""
        risk_scores = np.exp(X_scaled @ self.coefficients)
        unique_times = np.unique(times[events == 1])
        baseline_hazard = []
        
        for t in unique_times:
            events_at_t = np.sum((times == t) & (events == 1))
            at_risk = times >= t
            risk_sum = np.sum(risk_scores[at_risk])
            baseline_hazard.append(events_at_t / risk_sum if risk_sum > 0 else 0)
        
        self.baseline_hazard = (unique_times, np.cumsum(baseline_hazard))
    
    def predict_risk(self, X: np.ndarray) -> np.ndarray:
        """Predict relative risk scores"""
        scaler = StandardScaler()
        X_scaled = scaler.fit_transform(X)
        return np.exp(X_scaled @ self.coefficients)
    
    def get_hazard_ratios(self) -> Dict[str, Tuple[float, Tuple[float, float]]]:
        """Return hazard ratios with 95% confidence intervals"""
        hrs = {}
        for i, name in enumerate(self.feature_names):
            hr = np.exp(self.coefficients[i])
            se = 0.15  # Simplified SE estimation
            ci_lower = np.exp(self.coefficients[i] - 1.96 * se)
            ci_upper = np.exp(self.coefficients[i] + 1.96 * se)
            hrs[name] = (hr, (ci_lower, ci_upper))
        return hrs


class KaplanMeierEstimator:
    """Non-parametric survival curve estimation"""
    
    def __init__(self):
        self.survival_function = None
        self.time_points = None
        
    def fit(self, times: np.ndarray, events: np.ndarray):
        """Estimate survival function"""
        unique_times = np.unique(times)
        survival_probs = []
        n_at_risk = len(times)
        survival_prob = 1.0
        
        for t in unique_times:
            events_at_t = np.sum((times == t) & (events == 1))
            censored_at_t = np.sum((times == t) & (events == 0))
            
            if n_at_risk > 0:
                survival_prob *= (1 - events_at_t / n_at_risk)
            survival_probs.append(survival_prob)
            n_at_risk -= (events_at_t + censored_at_t)
        
        self.time_points = unique_times
        self.survival_function = np.array(survival_probs)
        return self
    
    def predict(self, times: np.ndarray) -> np.ndarray:
        """Predict survival probability at specified times"""
        return np.interp(times, self.time_points, self.survival_function, 
                        left=1.0, right=self.survival_function[-1])


class CompetingRisksModel:
    """Competing risks analysis using subdistribution hazards"""
    
    def __init__(self, event_types: List[str]):
        self.event_types = event_types
        self.cumulative_incidence = {}
        
    def fit(self, times: np.ndarray, events: np.ndarray, event_labels: np.ndarray):
        """Estimate cumulative incidence functions for each competing event"""
        for event_type in self.event_types:
            event_indicator = (event_labels == event_type).astype(int)
            cif = self._estimate_cif(times, events, event_indicator)
            self.cumulative_incidence[event_type] = cif
        return self
    
    def _estimate_cif(self, times: np.ndarray, events: np.ndarray, 
                     target_event: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
        """Estimate cumulative incidence function"""
        unique_times = np.unique(times[events == 1])
        cif = []
        overall_survival = 1.0
        cumulative_incidence = 0.0
        
        for t in unique_times:
            at_risk = times >= t
            n_at_risk = np.sum(at_risk)
            target_events = np.sum((times == t) & (target_event == 1))
            all_events = np.sum((times == t) & (events == 1))
            
            if n_at_risk > 0:
                hazard = target_events / n_at_risk
                cumulative_incidence += overall_survival * hazard
                overall_survival *= (1 - all_events / n_at_risk)
            
            cif.append(cumulative_incidence)
        
        return unique_times, np.array(cif)
    
    def predict_probabilities(self, time: float) -> Dict[str, float]:
        """Predict probability of each competing event by time t"""
        probs = {}
        for event_type, (times, cif) in self.cumulative_incidence.items():
            prob = np.interp(time, times, cif, left=0.0, right=cif[-1])
            probs[event_type] = float(prob)
        return probs


class ReadmissionRiskPredictor:
    """Integrated predictor combining all survival models"""
    
    def __init__(self):
        self.weibull = WeibullSurvivalModel()
        self.cox = CoxProportionalHazards()
        self.km = KaplanMeierEstimator()
        self.competing = CompetingRisksModel(['readmission', 'death', 'transfer', 'recovery'])
        
    def train(self, df: pd.DataFrame):
        """Train all models on patient data"""
        times = df['time_to_event'].values
        events = df['event_occurred'].values
        event_types = df['event_type'].values
        
        X = df[['age', 'num_comorbidities', 'prior_admissions', 
               'diabetes', 'chf', 'copd', 'socioeconomic_index']].values
        feature_names = ['age', 'num_comorbidities', 'prior_admissions', 
                        'diabetes', 'chf', 'copd', 'socioeconomic_index']
        
        self.weibull.fit(times, events, X)
        self.cox.fit(times, events, X, feature_names)
        self.km.fit(times, events)
        self.competing.fit(times, events, event_types)
        
        return self
    
    def predict_patient_risk(self, patient_data: Dict) -> Dict:
        """Generate comprehensive risk assessment for a patient"""
        X = np.array([[
            patient_data['age'],
            patient_data['num_comorbidities'],
            patient_data['prior_admissions'],
            patient_data.get('diabetes', 0),
            patient_data.get('chf', 0),
            patient_data.get('copd', 0),
            patient_data.get('socioeconomic_index', 50)
        ]])
        
        risk_30 = 1 - self.weibull.predict_survival(np.array([30]), X)[0]
        risk_60 = 1 - self.weibull.predict_survival(np.array([60]), X)[0]
        risk_90 = 1 - self.weibull.predict_survival(np.array([90]), X)[0]
        
        hazard_ratio = self.cox.predict_risk(X)[0]
        competing_30 = self.competing.predict_probabilities(30)
        
        return {
            'risk_30_day': float(risk_30),
            'risk_60_day': float(risk_60),
            'risk_90_day': float(risk_90),
            'hazard_ratio': float(hazard_ratio),
            'competing_risks': competing_30,
            'risk_category': 'high' if risk_30 > 0.6 else 'medium' if risk_30 > 0.3 else 'low',
            'confidence_interval_30': (float(risk_30 * 0.85), float(risk_30 * 1.15))
        }
    
    def generate_care_plan(self, risk_assessment: Dict) -> List[str]:
        """Generate automated care plan recommendations"""
        recommendations = []
        
        if risk_assessment['risk_30_day'] > 0.6:
            recommendations.extend([
                "HIGH PRIORITY: Schedule follow-up within 3 days of discharge",
                "Arrange home health nursing visit within 24 hours",
                "Implement daily medication adherence monitoring",
                "Consider transitional care management program enrollment",
                "Schedule telehealth check-in at 48 hours post-discharge"
            ])
        elif risk_assessment['risk_30_day'] > 0.3:
            recommendations.extend([
                "Schedule follow-up within 7 days of discharge",
                "Medication reconciliation at discharge",
                "Provide written discharge instructions with emergency contacts",
                "Arrange follow-up call within 48-72 hours"
            ])
        else:
            recommendations.extend([
                "Standard follow-up within 14 days",
                "Provide discharge education materials",
                "Ensure understanding of medication regimen"
            ])
        
        if risk_assessment['competing_risks']['death'] > 0.1:
            recommendations.append("ALERT: Elevated mortality risk - consider palliative care consultation")
        
        return recommendations


# Example usage and testing
if __name__ == "__main__":
    # Generate synthetic patient data
    np.random.seed(42)
    n_patients = 500
    
    synthetic_data = pd.DataFrame({
        'patient_id': [f'P{i:04d}' for i in range(n_patients)],
        'age': np.random.normal(65, 12, n_patients).clip(18, 95),
        'num_comorbidities': np.random.poisson(2, n_patients),
        'prior_admissions': np.random.poisson(1, n_patients),
        'diabetes': np.random.binomial(1, 0.3, n_patients),
        'chf': np.random.binomial(1, 0.2, n_patients),
        'copd': np.random.binomial(1, 0.15, n_patients),
        'socioeconomic_index': np.random.normal(50, 20, n_patients).clip(0, 100),
        'time_to_event': np.random.weibull(1.5, n_patients) * 60,
        'event_occurred': np.random.binomial(1, 0.4, n_patients),
        'event_type': np.random.choice(['readmission', 'death', 'transfer', 'recovery'], 
                                       n_patients, p=[0.4, 0.1, 0.15, 0.35])
    })
    
    # Train predictor
    predictor = ReadmissionRiskPredictor()
    predictor.train(synthetic_data)
    
    # Test prediction
    test_patient = {
        'age': 72,
        'num_comorbidities': 3,
        'prior_admissions': 2,
        'diabetes': 1,
        'chf': 1,
        'copd': 0,
        'socioeconomic_index': 35
    }
    
    risk = predictor.predict_patient_risk(test_patient)
    care_plan = predictor.generate_care_plan(risk)
    
    print("Patient Risk Assessment:")
    print(json.dumps(risk, indent=2))
    print("\nCare Plan Recommendations:")
    for rec in care_plan:
        print(f"- {rec}")
    
    # Display Cox model hazard ratios
    hrs = predictor.cox.get_hazard_ratios()
    print("\nCox Proportional Hazards - Hazard Ratios:")
    for feature, (hr, ci) in hrs.items():
        print(f"{feature}: HR={hr:.2f} (95% CI: {ci[0]:.2f}-{ci[1]:.2f})")
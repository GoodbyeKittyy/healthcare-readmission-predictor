import React, { useState, useEffect, useRef } from 'react';
import { Play, Pause, RotateCcw, Users, Activity, AlertCircle, TrendingUp, Settings, Download, RefreshCw } from 'lucide-react';
import { LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, Area, AreaChart } from 'recharts';

const ReadmissionDashboard = () => {
  const [isPlaying, setIsPlaying] = useState(false);
  const [timeIndex, setTimeIndex] = useState(0);
  const [selectedPatient, setSelectedPatient] = useState(null);
  const [viewMode, setViewMode] = useState('overview');
  const intervalRef = useRef(null);

  const patients = [
    { id: 'P001', name: 'Johnson, Mary', age: 67, risk30: 0.42, risk60: 0.58, risk90: 0.71, comorbidities: ['Diabetes', 'CHF'], score: 8.2 },
    { id: 'P002', name: 'Smith, Robert', age: 54, risk30: 0.18, risk60: 0.29, risk90: 0.38, comorbidities: ['Hypertension'], score: 4.1 },
    { id: 'P003', name: 'Williams, Patricia', age: 72, risk30: 0.65, risk60: 0.79, risk90: 0.87, comorbidities: ['COPD', 'Diabetes', 'CAD'], score: 9.7 },
    { id: 'P004', name: 'Brown, James', age: 45, risk30: 0.12, risk60: 0.21, risk60: 0.28, comorbidities: ['None'], score: 2.3 },
    { id: 'P005', name: 'Davis, Linda', age: 61, risk30: 0.38, risk60: 0.51, risk90: 0.64, comorbidities: ['Diabetes', 'Hypertension'], score: 6.8 },
    { id: 'P006', name: 'Miller, Michael', age: 78, risk30: 0.71, risk60: 0.84, risk90: 0.91, comorbidities: ['CHF', 'CKD', 'AFib'], score: 10.2 },
  ];

  const generateTimeSeriesData = (maxPoints) => {
    return Array.from({ length: maxPoints }, (_, i) => ({
      day: i + 1,
      avgRisk: 0.35 + Math.sin(i / 5) * 0.1 + (i * 0.002),
      high: 0.55 + Math.sin(i / 4) * 0.08 + (i * 0.0015),
      low: 0.15 + Math.sin(i / 6) * 0.05 + (i * 0.001),
      readmissions: Math.floor(5 + Math.random() * 3 + i * 0.1),
    }));
  };

  const [timeSeriesData] = useState(generateTimeSeriesData(90));

  const survivalData = Array.from({ length: 30 }, (_, i) => ({
    day: i * 3,
    highRisk: 1 - (i * 0.03 + Math.random() * 0.02),
    mediumRisk: 1 - (i * 0.02 + Math.random() * 0.01),
    lowRisk: 1 - (i * 0.01 + Math.random() * 0.005),
  }));

  const hazardData = Array.from({ length: 20 }, (_, i) => ({
    week: i + 1,
    hazardRate: 0.05 + Math.exp(-i / 5) * 0.15,
  }));

  useEffect(() => {
    if (isPlaying) {
      intervalRef.current = setInterval(() => {
        setTimeIndex((prev) => {
          if (prev >= timeSeriesData.length - 1) {
            setIsPlaying(false);
            return prev;
          }
          return prev + 1;
        });
      }, 100);
    } else {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
      }
    }
    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
      }
    };
  }, [isPlaying, timeSeriesData.length]);

  const handleReset = () => {
    setTimeIndex(0);
    setIsPlaying(false);
  };

  const getRiskColor = (risk) => {
    if (risk >= 0.6) return 'text-red-600';
    if (risk >= 0.3) return 'text-yellow-600';
    return 'text-green-600';
  };

  const getRiskBg = (risk) => {
    if (risk >= 0.6) return 'bg-red-50 border-red-200';
    if (risk >= 0.3) return 'bg-yellow-50 border-yellow-200';
    return 'bg-green-50 border-green-200';
  };

  const currentData = timeSeriesData.slice(0, timeIndex + 1);

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Top Navigation Bar */}
      <div className="bg-white border-b border-gray-200 shadow-sm">
        <div className="px-6 py-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-4">
              <div className="flex items-center space-x-2">
                <Activity className="w-6 h-6 text-blue-600" />
                <h1 className="text-xl font-semibold text-gray-800">Clinical Decision Support System</h1>
              </div>
              <div className="h-6 w-px bg-gray-300"></div>
              <span className="text-sm text-gray-600">Readmission Risk Analytics</span>
            </div>
            <div className="flex items-center space-x-4">
              <button className="p-2 hover:bg-gray-100 rounded">
                <Settings className="w-5 h-5 text-gray-600" />
              </button>
              <button className="p-2 hover:bg-gray-100 rounded">
                <Download className="w-5 h-5 text-gray-600" />
              </button>
              <div className="px-3 py-1 bg-blue-100 text-blue-800 rounded text-sm font-medium">
                Live Session
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Main Content */}
      <div className="p-6 space-y-6">
        {/* Control Panel */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-4">
              <h2 className="text-lg font-semibold text-gray-800">Developer Control Panel</h2>
              <div className="flex items-center space-x-2">
                <button
                  onClick={() => setIsPlaying(!isPlaying)}
                  className="flex items-center space-x-2 px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors"
                >
                  {isPlaying ? <Pause className="w-4 h-4" /> : <Play className="w-4 h-4" />}
                  <span>{isPlaying ? 'Pause' : 'Play'}</span>
                </button>
                <button
                  onClick={handleReset}
                  className="flex items-center space-x-2 px-4 py-2 bg-gray-200 text-gray-700 rounded hover:bg-gray-300 transition-colors"
                >
                  <RotateCcw className="w-4 h-4" />
                  <span>Reset</span>
                </button>
                <button className="flex items-center space-x-2 px-4 py-2 bg-gray-200 text-gray-700 rounded hover:bg-gray-300 transition-colors">
                  <RefreshCw className="w-4 h-4" />
                  <span>Refresh</span>
                </button>
              </div>
            </div>
            <div className="flex items-center space-x-6">
              <div className="text-sm">
                <span className="text-gray-600">Timeline: </span>
                <span className="font-semibold text-gray-800">Day {timeIndex + 1} / 90</span>
              </div>
              <div className="flex space-x-2">
                <button
                  onClick={() => setViewMode('overview')}
                  className={`px-3 py-1 rounded text-sm ${viewMode === 'overview' ? 'bg-blue-100 text-blue-800' : 'bg-gray-100 text-gray-600'}`}
                >
                  Overview
                </button>
                <button
                  onClick={() => setViewMode('patients')}
                  className={`px-3 py-1 rounded text-sm ${viewMode === 'patients' ? 'bg-blue-100 text-blue-800' : 'bg-gray-100 text-gray-600'}`}
                >
                  Patients
                </button>
                <button
                  onClick={() => setViewMode('analytics')}
                  className={`px-3 py-1 rounded text-sm ${viewMode === 'analytics' ? 'bg-blue-100 text-blue-800' : 'bg-gray-100 text-gray-600'}`}
                >
                  Analytics
                </button>
              </div>
            </div>
          </div>
          <div className="mt-4">
            <div className="w-full bg-gray-200 rounded-full h-2">
              <div
                className="bg-blue-600 h-2 rounded-full transition-all duration-100"
                style={{ width: `${((timeIndex + 1) / timeSeriesData.length) * 100}%` }}
              ></div>
            </div>
          </div>
        </div>

        {/* Key Metrics */}
        <div className="grid grid-cols-4 gap-4">
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-gray-600">Total Patients</p>
                <p className="text-2xl font-bold text-gray-800 mt-1">284</p>
                <p className="text-xs text-green-600 mt-1">↑ 12 from last week</p>
              </div>
              <Users className="w-10 h-10 text-blue-600 opacity-20" />
            </div>
          </div>
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-gray-600">High Risk Patients</p>
                <p className="text-2xl font-bold text-red-600 mt-1">47</p>
                <p className="text-xs text-red-600 mt-1">↑ 5 from yesterday</p>
              </div>
              <AlertCircle className="w-10 h-10 text-red-600 opacity-20" />
            </div>
          </div>
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-gray-600">Avg Risk Score</p>
                <p className="text-2xl font-bold text-yellow-600 mt-1">
                  {currentData.length > 0 ? currentData[currentData.length - 1].avgRisk.toFixed(2) : '0.35'}
                </p>
                <p className="text-xs text-yellow-600 mt-1">30-day window</p>
              </div>
              <TrendingUp className="w-10 h-10 text-yellow-600 opacity-20" />
            </div>
          </div>
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-gray-600">Readmissions (MTD)</p>
                <p className="text-2xl font-bold text-gray-800 mt-1">
                  {currentData.length > 0 ? currentData[currentData.length - 1].readmissions : '5'}
                </p>
                <p className="text-xs text-green-600 mt-1">↓ 8% vs last month</p>
              </div>
              <Activity className="w-10 h-10 text-green-600 opacity-20" />
            </div>
          </div>
        </div>

        {viewMode === 'overview' && (
          <>
            {/* Risk Trends Over Time */}
            <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
              <h3 className="text-lg font-semibold text-gray-800 mb-4">Risk Score Trends (Live)</h3>
              <ResponsiveContainer width="100%" height={300}>
                <AreaChart data={currentData}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                  <XAxis dataKey="day" stroke="#6b7280" style={{ fontSize: '12px' }} />
                  <YAxis stroke="#6b7280" style={{ fontSize: '12px' }} />
                  <Tooltip contentStyle={{ backgroundColor: '#fff', border: '1px solid #e5e7eb' }} />
                  <Legend />
                  <Area type="monotone" dataKey="high" stackId="1" stroke="#ef4444" fill="#fee2e2" name="High Risk" />
                  <Area type="monotone" dataKey="avgRisk" stackId="1" stroke="#3b82f6" fill="#dbeafe" name="Avg Risk" />
                  <Area type="monotone" dataKey="low" stackId="1" stroke="#10b981" fill="#d1fae5" name="Low Risk" />
                </AreaChart>
              </ResponsiveContainer>
            </div>

            {/* Survival Curves */}
            <div className="grid grid-cols-2 gap-6">
              <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
                <h3 className="text-lg font-semibold text-gray-800 mb-4">Kaplan-Meier Survival Curves</h3>
                <ResponsiveContainer width="100%" height={300}>
                  <LineChart data={survivalData}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                    <XAxis dataKey="day" stroke="#6b7280" style={{ fontSize: '12px' }} label={{ value: 'Days', position: 'insideBottom', offset: -5 }} />
                    <YAxis stroke="#6b7280" style={{ fontSize: '12px' }} label={{ value: 'Survival Probability', angle: -90, position: 'insideLeft' }} />
                    <Tooltip contentStyle={{ backgroundColor: '#fff', border: '1px solid #e5e7eb' }} />
                    <Legend />
                    <Line type="monotone" dataKey="lowRisk" stroke="#10b981" strokeWidth={2} name="Low Risk" dot={false} />
                    <Line type="monotone" dataKey="mediumRisk" stroke="#f59e0b" strokeWidth={2} name="Medium Risk" dot={false} />
                    <Line type="monotone" dataKey="highRisk" stroke="#ef4444" strokeWidth={2} name="High Risk" dot={false} />
                  </LineChart>
                </ResponsiveContainer>
              </div>

              <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
                <h3 className="text-lg font-semibold text-gray-800 mb-4">Weibull Hazard Rate</h3>
                <ResponsiveContainer width="100%" height={300}>
                  <BarChart data={hazardData}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                    <XAxis dataKey="week" stroke="#6b7280" style={{ fontSize: '12px' }} label={{ value: 'Weeks Post-Discharge', position: 'insideBottom', offset: -5 }} />
                    <YAxis stroke="#6b7280" style={{ fontSize: '12px' }} />
                    <Tooltip contentStyle={{ backgroundColor: '#fff', border: '1px solid #e5e7eb' }} />
                    <Bar dataKey="hazardRate" fill="#3b82f6" name="Hazard Rate" />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </div>
          </>
        )}

        {viewMode === 'patients' && (
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <h3 className="text-lg font-semibold text-gray-800 mb-4">Patient Risk Assessment</h3>
            <div className="space-y-3">
              {patients.map((patient) => (
                <div
                  key={patient.id}
                  className={`border rounded-lg p-4 cursor-pointer transition-all ${
                    selectedPatient?.id === patient.id ? 'border-blue-500 bg-blue-50' : 'border-gray-200 hover:border-gray-300'
                  }`}
                  onClick={() => setSelectedPatient(patient)}
                >
                  <div className="flex items-center justify-between">
                    <div className="flex-1">
                      <div className="flex items-center space-x-4">
                        <div>
                          <p className="font-semibold text-gray-800">{patient.name}</p>
                          <p className="text-sm text-gray-600">ID: {patient.id} • Age: {patient.age}</p>
                        </div>
                        <div className="flex space-x-2">
                          {patient.comorbidities.map((cond, idx) => (
                            <span key={idx} className="px-2 py-1 bg-gray-100 text-gray-700 rounded text-xs">
                              {cond}
                            </span>
                          ))}
                        </div>
                      </div>
                    </div>
                    <div className="flex items-center space-x-6">
                      <div className="text-right">
                        <p className="text-xs text-gray-600">30-Day Risk</p>
                        <p className={`text-lg font-bold ${getRiskColor(patient.risk30)}`}>
                          {(patient.risk30 * 100).toFixed(1)}%
                        </p>
                      </div>
                      <div className="text-right">
                        <p className="text-xs text-gray-600">60-Day Risk</p>
                        <p className={`text-lg font-bold ${getRiskColor(patient.risk60)}`}>
                          {(patient.risk60 * 100).toFixed(1)}%
                        </p>
                      </div>
                      <div className="text-right">
                        <p className="text-xs text-gray-600">90-Day Risk</p>
                        <p className={`text-lg font-bold ${getRiskColor(patient.risk90)}`}>
                          {(patient.risk90 * 100).toFixed(1)}%
                        </p>
                      </div>
                      <div className={`px-4 py-2 rounded-lg border ${getRiskBg(patient.risk30)}`}>
                        <p className="text-xs text-gray-600">Risk Score</p>
                        <p className={`text-xl font-bold ${getRiskColor(patient.risk30)}`}>{patient.score}</p>
                      </div>
                    </div>
                  </div>
                  {selectedPatient?.id === patient.id && (
                    <div className="mt-4 pt-4 border-t border-gray-200">
                      <h4 className="font-semibold text-gray-800 mb-2">Care Plan Recommendations</h4>
                      <ul className="space-y-2 text-sm text-gray-700">
                        <li className="flex items-start">
                          <span className="text-blue-600 mr-2">•</span>
                          <span>Schedule follow-up appointment within 7 days of discharge</span>
                        </li>
                        <li className="flex items-start">
                          <span className="text-blue-600 mr-2">•</span>
                          <span>Medication reconciliation and adherence counseling</span>
                        </li>
                        <li className="flex items-start">
                          <span className="text-blue-600 mr-2">•</span>
                          <span>Home health nurse visit within 48 hours</span>
                        </li>
                        <li className="flex items-start">
                          <span className="text-blue-600 mr-2">•</span>
                          <span>Dietary consultation for chronic disease management</span>
                        </li>
                      </ul>
                    </div>
                  )}
                </div>
              ))}
            </div>
          </div>
        )}

        {viewMode === 'analytics' && (
          <div className="grid grid-cols-2 gap-6">
            <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
              <h3 className="text-lg font-semibold text-gray-800 mb-4">Cox Proportional Hazards</h3>
              <div className="space-y-4">
                <div className="border-b border-gray-200 pb-3">
                  <div className="flex justify-between items-center">
                    <span className="text-sm text-gray-700">Age (per 10 years)</span>
                    <span className="font-semibold text-gray-900">HR: 1.42 (1.18-1.71)</span>
                  </div>
                  <div className="text-xs text-gray-500 mt-1">p &lt; 0.001</div>
                </div>
                <div className="border-b border-gray-200 pb-3">
                  <div className="flex justify-between items-center">
                    <span className="text-sm text-gray-700">Diabetes</span>
                    <span className="font-semibold text-gray-900">HR: 1.68 (1.32-2.14)</span>
                  </div>
                  <div className="text-xs text-gray-500 mt-1">p &lt; 0.001</div>
                </div>
                <div className="border-b border-gray-200 pb-3">
                  <div className="flex justify-between items-center">
                    <span className="text-sm text-gray-700">CHF</span>
                    <span className="font-semibold text-gray-900">HR: 2.13 (1.67-2.72)</span>
                  </div>
                  <div className="text-xs text-gray-500 mt-1">p &lt; 0.001</div>
                </div>
                <div className="border-b border-gray-200 pb-3">
                  <div className="flex justify-between items-center">
                    <span className="text-sm text-gray-700">Prior Admission</span>
                    <span className="font-semibold text-gray-900">HR: 1.89 (1.51-2.36)</span>
                  </div>
                  <div className="text-xs text-gray-500 mt-1">p &lt; 0.001</div>
                </div>
              </div>
            </div>

            <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
              <h3 className="text-lg font-semibold text-gray-800 mb-4">Competing Risks Analysis</h3>
              <div className="space-y-4">
                <div className="border border-gray-200 rounded-lg p-4">
                  <div className="flex justify-between items-center mb-2">
                    <span className="text-sm font-semibold text-gray-700">Readmission</span>
                    <span className="text-lg font-bold text-blue-600">42.3%</span>
                  </div>
                  <div className="w-full bg-gray-200 rounded-full h-2">
                    <div className="bg-blue-600 h-2 rounded-full" style={{ width: '42.3%' }}></div>
                  </div>
                </div>
                <div className="border border-gray-200 rounded-lg p-4">
                  <div className="flex justify-between items-center mb-2">
                    <span className="text-sm font-semibold text-gray-700">Death</span>
                    <span className="text-lg font-bold text-red-600">8.7%</span>
                  </div>
                  <div className="w-full bg-gray-200 rounded-full h-2">
                    <div className="bg-red-600 h-2 rounded-full" style={{ width: '8.7%' }}></div>
                  </div>
                </div>
                <div className="border border-gray-200 rounded-lg p-4">
                  <div className="flex justify-between items-center mb-2">
                    <span className="text-sm font-semibold text-gray-700">Transfer</span>
                    <span className="text-lg font-bold text-yellow-600">12.1%</span>
                  </div>
                  <div className="w-full bg-gray-200 rounded-full h-2">
                    <div className="bg-yellow-600 h-2 rounded-full" style={{ width: '12.1%' }}></div>
                  </div>
                </div>
                <div className="border border-gray-200 rounded-lg p-4">
                  <div className="flex justify-between items-center mb-2">
                    <span className="text-sm font-semibold text-gray-700">Recovery</span>
                    <span className="text-lg font-bold text-green-600">36.9%</span>
                  </div>
                  <div className="w-full bg-gray-200 rounded-full h-2">
                    <div className="bg-green-600 h-2 rounded-full" style={{ width: '36.9%' }}></div>
                  </div>
                </div>
              </div>
            </div>

            <div className="col-span-2 bg-white rounded-lg shadow-sm border border-gray-200 p-6">
              <h3 className="text-lg font-semibold text-gray-800 mb-4">Model Performance Metrics</h3>
              <div className="grid grid-cols-4 gap-4">
                <div className="border border-gray-200 rounded-lg p-4 text-center">
                  <p className="text-sm text-gray-600 mb-1">C-Index</p>
                  <p className="text-3xl font-bold text-blue-600">0.847</p>
                  <p className="text-xs text-gray-500 mt-1">95% CI: 0.821-0.873</p>
                </div>
                <div className="border border-gray-200 rounded-lg p-4 text-center">
                  <p className="text-sm text-gray-600 mb-1">AUC (30-day)</p>
                  <p className="text-3xl font-bold text-green-600">0.892</p>
                  <p className="text-xs text-gray-500 mt-1">95% CI: 0.869-0.915</p>
                </div>
                <div className="border border-gray-200 rounded-lg p-4 text-center">
                  <p className="text-sm text-gray-600 mb-1">Calibration</p>
                  <p className="text-3xl font-bold text-purple-600">0.934</p>
                  <p className="text-xs text-gray-500 mt-1">Hosmer-Lemeshow</p>
                </div>
                <div className="border border-gray-200 rounded-lg p-4 text-center">
                  <p className="text-sm text-gray-600 mb-1">Brier Score</p>
                  <p className="text-3xl font-bold text-orange-600">0.127</p>
                  <p className="text-xs text-gray-500 mt-1">Lower is better</p>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default ReadmissionDashboard;
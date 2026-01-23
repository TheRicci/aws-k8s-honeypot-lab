#!/usr/bin/env python3
"""
Threat Intelligence Central Service
A simple threat intelligence aggregator for the honeypot lab
"""

import json
import logging
import os
import time
from datetime import datetime
from flask import Flask, jsonify, request
import requests
from elasticsearch import Elasticsearch
import schedule

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Configuration
ES_HOST = os.getenv('ES_HOST', 'http://localhost:9200')
DATA_DIR = os.getenv('DATA_DIR', '/app/data')

class ThreatCentral:
    def __init__(self):
        self.threats = []
        self.load_threats()

    def load_threats(self):
        """Load existing threat data"""
        try:
            with open(f"{DATA_DIR}/threats.json", 'r') as f:
                self.threats = json.load(f)
        except FileNotFoundError:
            self.threats = []
            logger.info("No existing threat data found, starting fresh")

    def save_threats(self):
        """Save threat data to disk"""
        with open(f"{DATA_DIR}/threats.json", 'w') as f:
            json.dump(self.threats, f, indent=2)

    def add_threat(self, threat_data):
        """Add a new threat intelligence item"""
        threat = {
            'id': len(self.threats) + 1,
            'timestamp': datetime.utcnow().isoformat(),
            'source': threat_data.get('source', 'unknown'),
            'type': threat_data.get('type', 'unknown'),
            'data': threat_data,
            'severity': threat_data.get('severity', 'low')
        }

        self.threats.append(threat)
        self.save_threats()
        logger.info(f"Added new threat: {threat['id']}")
        return threat

    def get_threats(self, limit=100):
        """Get recent threats"""
        return self.threats[-limit:]

# Initialize threat central
threat_central = ThreatCentral()

@app.route('/health')
def health():
    return jsonify({'status': 'healthy', 'threats_count': len(threat_central.threats)})

@app.route('/threats', methods=['GET', 'POST'])
def threats():
    if request.method == 'POST':
        data = request.get_json()
        if not data:
            return jsonify({'error': 'No data provided'}), 400

        threat = threat_central.add_threat(data)
        return jsonify(threat), 201

    else:
        limit = int(request.args.get('limit', 100))
        threats = threat_central.get_threats(limit)
        return jsonify(threats)

@app.route('/threats/<int:threat_id>')
def get_threat(threat_id):
    threat = next((t for t in threat_central.threats if t['id'] == threat_id), None)
    if threat:
        return jsonify(threat)
    return jsonify({'error': 'Threat not found'}), 404

@app.route('/stats')
def stats():
    """Get threat statistics"""
    stats = {
        'total_threats': len(threat_central.threats),
        'threat_types': {},
        'sources': {},
        'severity_distribution': {}
    }

    for threat in threat_central.threats:
        # Count by type
        ttype = threat.get('type', 'unknown')
        stats['threat_types'][ttype] = stats['threat_types'].get(ttype, 0) + 1

        # Count by source
        source = threat.get('source', 'unknown')
        stats['sources'][source] = stats['sources'].get(source, 0) + 1

        # Count by severity
        severity = threat.get('severity', 'unknown')
        stats['severity_distribution'][severity] = stats['severity_distribution'].get(severity, 0) + 1

    return jsonify(stats)

if __name__ == '__main__':
    logger.info("Starting Threat Central Service...")
    app.run(host='0.0.0.0', port=8080, debug=False)
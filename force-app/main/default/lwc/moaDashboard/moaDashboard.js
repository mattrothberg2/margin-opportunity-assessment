import { LightningElement, track } from 'lwc';
import runScan from '@salesforce/apex/MOA_ScanController.runScan';
import getLastScanResult from '@salesforce/apex/MOA_ScanController.getLastScanResult';

export default class MoaDashboard extends LightningElement {
    @track scanResult = null;
    @track isScanning = false;
    @track error = null;

    get hasResult() {
        return this.scanResult !== null;
    }

    connectedCallback() {
        this.loadLastResult();
    }

    async loadLastResult() {
        try {
            const result = await getLastScanResult();
            if (result) {
                this.scanResult = JSON.parse(result);
            }
        } catch (err) {
            // No previous result — that's fine
        }
    }

    async handleRunScan() {
        this.isScanning = true;
        this.error = null;
        try {
            const resultJson = await runScan();
            this.scanResult = JSON.parse(resultJson);
        } catch (err) {
            this.error = err.body ? err.body.message : 'An error occurred during the scan.';
        } finally {
            this.isScanning = false;
        }
    }
}

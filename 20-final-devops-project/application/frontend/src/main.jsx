import React, { useCallback, useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';

const API = '/api/incidents';
const NEXT_STATUS = { OPEN: 'INVESTIGATING', INVESTIGATING: 'RESOLVED', RESOLVED: 'OPEN' };
const FILTERS = ['ALL', 'OPEN', 'INVESTIGATING', 'RESOLVED'];

function since(iso) {
  const mins = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 60000));
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.round(mins / 60);
  return hours < 48 ? `${hours}h ago` : `${Math.round(hours / 24)}d ago`;
}

function App() {
  const [incidents, setIncidents] = useState([]);
  const [stats, setStats] = useState({ total: 0, open: 0, investigating: 0, resolved: 0, sev1_open: 0 });
  const [filter, setFilter] = useState('ALL');
  const [showForm, setShowForm] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    try {
      setError('');
      const [list, summary] = await Promise.all([fetch(API), fetch(`${API}/stats`)]);
      if (!list.ok || !summary.ok) throw new Error('API unavailable');
      setIncidents(await list.json());
      setStats(await summary.json());
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const advance = async (incident) => {
    await fetch(`${API}/${incident.id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: NEXT_STATUS[incident.status] }),
    });
    load();
  };

  const remove = async (incident) => {
    await fetch(`${API}/${incident.id}`, { method: 'DELETE' });
    load();
  };

  const create = async (event) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const resp = await fetch(API, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(Object.fromEntries(form.entries())),
    });
    if (!resp.ok) {
      setError(`Could not create incident (HTTP ${resp.status})`);
      return;
    }
    setShowForm(false);
    load();
  };

  const visible = filter === 'ALL' ? incidents : incidents.filter((i) => i.status === filter);

  return (
    <div className="app">
      <aside className="sidebar">
        <div className="brand">
          <span className="brand-mark">!</span>
          <div>
            <b>IncidentDesk</b>
            <small>DevOps final project</small>
          </div>
        </div>
        <nav>
          <a className="active">Incidents</a>
          <a>Services</a>
          <a>On-call</a>
          <a>Postmortems</a>
        </nav>
        <div className="pipeline-card">
          <strong>How this got here</strong>
          <ol>
            <li>GitHub Actions: test, scan, build</li>
            <li>Image pushed to GHCR</li>
            <li>Argo CD synced the Helm chart</li>
            <li>Prometheus watching /metrics</li>
          </ol>
        </div>
      </aside>

      <main className="main">
        <header>
          <div>
            <p className="eyebrow">PRODUCTION / INCIDENTS</p>
            <h1>Incident overview</h1>
            <p className="muted">Everything that is on fire, being looked at, or already put out.</p>
          </div>
          <button className="primary" onClick={() => setShowForm(true)}>+ Declare incident</button>
        </header>

        {error && <div className="alert">{error}. Is the API up? Check /ready.</div>}

        <section className="stats">
          <Stat label="SEV1 open" value={stats.sev1_open} tone={stats.sev1_open ? 'danger' : 'ok'} />
          <Stat label="Open" value={stats.open} />
          <Stat label="Investigating" value={stats.investigating} />
          <Stat label="Resolved" value={stats.resolved} />
          <Stat label="Total" value={stats.total} />
        </section>

        <section className="panel">
          <div className="panel-head">
            <h2>Incidents</h2>
            <div className="filters">
              {FILTERS.map((f) => (
                <button key={f} className={filter === f ? 'selected' : ''} onClick={() => setFilter(f)}>
                  {f === 'ALL' ? 'All' : f.toLowerCase()}
                </button>
              ))}
            </div>
          </div>
          {loading ? (
            <div className="empty">Loading incidents...</div>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>Sev</th><th>Incident</th><th>Service</th><th>Owner</th><th>Status</th><th>Opened</th><th></th>
                </tr>
              </thead>
              <tbody>
                {visible.map((i) => (
                  <tr key={i.id}>
                    <td><span className={`sev ${i.severity.toLowerCase()}`}>{i.severity}</span></td>
                    <td><b>{i.title}</b><small>{i.description}</small></td>
                    <td><code>{i.service}</code></td>
                    <td>{i.assignee}</td>
                    <td><span className={`status ${i.status.toLowerCase()}`}>{i.status.toLowerCase()}</span></td>
                    <td className="muted">{since(i.created_at)}</td>
                    <td className="actions">
                      <button title={`Move to ${NEXT_STATUS[i.status].toLowerCase()}`} onClick={() => advance(i)}>&rarr;</button>
                      <button title="Delete" onClick={() => remove(i)}>&times;</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
          {!loading && !visible.length && <div className="empty">No incidents here. Enjoy the quiet.</div>}
        </section>
      </main>

      {showForm && (
        <div className="modal-backdrop" onClick={(e) => e.target === e.currentTarget && setShowForm(false)}>
          <form className="modal" onSubmit={create}>
            <h2>Declare an incident</h2>
            <label>Title<input name="title" required minLength={3} placeholder="e.g. Checkout returns 502" /></label>
            <label>Description<textarea name="description" placeholder="What are users seeing?" /></label>
            <div className="row">
              <label>Service<input name="service" required defaultValue="api-gateway" /></label>
              <label>Severity
                <select name="severity" defaultValue="SEV3">
                  <option>SEV1</option><option>SEV2</option><option>SEV3</option><option>SEV4</option>
                </select>
              </label>
            </div>
            <label>Owner<input name="assignee" defaultValue="on-call" /></label>
            <button className="primary full">Declare</button>
          </form>
        </div>
      )}
    </div>
  );
}

function Stat({ label, value, tone }) {
  return (
    <div className={`stat ${tone || ''}`}>
      <small>{label}</small>
      <strong>{value}</strong>
    </div>
  );
}

createRoot(document.getElementById('root')).render(<App />);

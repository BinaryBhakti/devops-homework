import { useState } from "react";

export default function App() {
  const [count, setCount] = useState(0);

  return (
    <div className="card">
      <h1>Hello World</h1>
      <p>React (built with Vite) running in Docker</p>
      <p>
        served as a static build by <code>nginx</code>
      </p>
      <button onClick={() => setCount((c) => c + 1)}>
        clicked {count} {count === 1 ? "time" : "times"}
      </button>
    </div>
  );
}

import { render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import App from './App';

function mockFetchOnce(data) {
  global.fetch = jest.fn().mockResolvedValue({
    ok: true,
    json: async () => data,
  });
}

beforeEach(() => {
  localStorage.clear();
});

afterEach(() => {
  jest.restoreAllMocks();
});

test('renders the CloudMart header', async () => {
  mockFetchOnce({ products: [] });
  render(<App />);
  expect(screen.getByText('CloudMart-b')).toBeInTheDocument();
  await screen.findByText(/No products found/i);
});

test('shows a message when no products are returned', async () => {
  mockFetchOnce({ products: [] });
  render(<App />);
  expect(await screen.findByText(/No products found/i)).toBeInTheDocument();
});

test('renders fetched products', async () => {
  mockFetchOnce({
    products: [
      { id: 'prod-001', name: 'Test Widget', description: 'A widget', price: 9.99, category: 'misc', stock: 5 },
    ],
  });
  render(<App />);
  expect(await screen.findByText('Test Widget')).toBeInTheDocument();
  expect(screen.getByText('$9.99')).toBeInTheDocument();
});
